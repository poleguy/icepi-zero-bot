#!/bin/bash

FPGA_BOARD=icepi-zero
FPGA_PACKAGE=CABGA256
OSS_CAD_SUITE=/opt/oss-cad-suite
IDLE_DELAY=30

SCRIPTDIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if [ -f $SCRIPTDIR/.env ]; then
    . $SCRIPTDIR/.env
fi
if [ -f .env ]; then
    . .env
fi

WORKDIR="$(mktemp -d)"
echo "Work dir: $WORKDIR"
trap "rm -r $WORKDIR" EXIT

fetch_asks() {
    curl --silent -H "Authorization: Bearer $WAFRN_TOKEN" "$WAFRN_URL/api/user/myAsks" > "$WORKDIR/asks.json"
    if [ $? -ne 0 ]; then
        echo "Failed to fetch asks."
        return 1
    fi
    count="$(jq -r ".asks | length" "$WORKDIR/asks.json")"

    if [ $count -le 0 ]; then
        return 1
    fi
    return 0
}

fetch_thread() {
    id="$1"
    INPUTFILE="$2"

    inReplyTo="$(jq -r '.asks[0].apObject | fromjson | .inReplyTo' "$WORKDIR/asks.json")"
    if [ "$inReplyTo" == "null" ]; then
        echo "Ask $id: inReplyTo is null"
        return 1
    fi

    curl --silent -H "Authorization: Bearer $WAFRN_TOKEN" "$WAFRN_URL/api/v2/search?page=0&startScroll=0&term=$inReplyTo" > "$WORKDIR/$id/thread_search.json"
    if [ $? -ne 0 ]; then
        echo "Ask $id: search for post $inReplyTo failed"
        return 1
    fi

    count="$(jq -r '.posts.posts | length' "$WORKDIR/$id/thread_search.json")"
    if [ $count -ne 1 ]; then
        echo "Ask $id: search found $count posts for $inReplyTo, expected exactly one"
        return 1
    fi

    jq -r '.posts.posts[0] | [(.ancestors | sort_by(.hierarchyLevel))[].content, .content] | join("\n")' "$WORKDIR/$id/thread_search.json" | hxremove -i 'a.mention' | html2text > "$INPUTFILE"
    echo "Ask $id: fetched thread"
}

process_ask() {
    id="$(jq -r ".asks[0].id" "$WORKDIR/asks.json")"

    echo "Processing ask $id..."

    ASKDIR="$WORKDIR/$id"
    OUTPUTDIR="$ASKDIR/output"
    INPUTFILE="$ASKDIR/message.txt"

    mkdir -p "$ASKDIR" "$OUTPUTDIR"
    jq -r ".asks[0].question" "$WORKDIR/asks.json" | perl -MHTML::Entities -pe 'decode_entities($_);' > "$INPUTFILE"

    if ! grep -q '[^[:space:]]' "$INPUTFILE"; then
        echo "Ask $id: Empty ask. Attempting to fetch thread..."
        if ! fetch_thread "$id" "$INPUTFILE"; then
            echo "Ask $id: Failed to fetch thread."
            jq --arg id "$id" -n -r \
                '{"content": "Empty ask without ancestor. Please ensure that your code is in a thread and the ask is replying to it.", "medias":[], "tags": "", "privacy": 10, "content_warning": "", "ask": $id, "mentionedUserIds": []}' \
                > "$OUTPUTDIR/request.json"
            curl --silent -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $WAFRN_TOKEN" -d "@$OUTPUTDIR/request.json" "$WAFRN_URL/api/v3/createPost" > /dev/null
            echo "Finished processing ask $id."
            return 1
        fi
    fi

    echo "Ask $id: Running synthesis..."
    podman run --rm -a=stdout -a=stderr --network=none \
        -v "$OUTPUTDIR:/output" -v "$SCRIPTDIR/code:/code:ro" \
        -v "$INPUTFILE:/input/message.txt:ro" -v "$SCRIPTDIR/scripts:/scripts:ro" \
        -v "$OSS_CAD_SUITE:/opt/oss-cad-suite/:ro" \
        -e FPGA_PACKAGE="$FPGA_PACKAGE" \
        --env-merge PATH='${PATH}:/opt/oss-cad-suite/bin' icepi-zero-bot-synth-container:latest \
        /scripts/synth.sh /input/message.txt /output /code > "$OUTPUTDIR/synth.log" 2>&1

    if [ $? -ne 0 ]; then
        echo "Ask $id: Synthesis failed."
        jq --arg id "$id" --rawfile content "$OUTPUTDIR/synth.log" -n -r \
            '{"content": ("```\n" + $content + "\n```"), "medias":[], "tags": "", "privacy": 10, "content_warning": "Synthesis failed.", "ask": $id, "mentionedUserIds": []}' \
            > "$OUTPUTDIR/request.json"
        curl --silent -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $WAFRN_TOKEN" -d "@$OUTPUTDIR/request.json" "$WAFRN_URL/api/v3/createPost" > /dev/null
        echo "Finished processing ask $id."
        return 1
    fi

    echo "<details><summary>Utilization</summary><table><thead><th><td><b>Cell</b></td><td><b>Used</b></td><td><b>Available</b></td><td><b>Usage</b></td></th></thead><tbody>" > "$OUTPUTDIR/utilization.html"
    jq -r '.utilization | to_entries[] | select(.value.used > 0) | "<tr><td><code>\(.key)</code></td><td>\(.value.used)</td><td>\(.value.available)</td><td>\(1000*.value.used / .value.available | round/10)%</td></tr>"' "$OUTPUTDIR/report.json" >> "$OUTPUTDIR/utilization.html"
    echo "</tbody></table></details>" >> "$OUTPUTDIR/utilization.html"

    echo "<details><summary>Timing</summary><table><thead><th><td><b>Clock</b></td><td><b>Achieved</b></td><td><b>Constraint</b></td></th></thead><tbody>" > "$OUTPUTDIR/timing.html"
    jq -r '.fmax | to_entries[] | "<tr><td><code>\(.key)</code></td><td>\(.value.achieved*100 | round/100) MHz</td><td>\(.value.constraint*100 | round/100) MHz</td></tr>"' "$OUTPUTDIR/report.json" >> "$OUTPUTDIR/timing.html"
    echo "</tbody></table></details>" >> "$OUTPUTDIR/timing.html"

    cat "$OUTPUTDIR/utilization.html" "$OUTPUTDIR/timing.html" > "$OUTPUTDIR/report.html"

    echo "Ask $id: Flashing bitstream..."
    "$OSS_CAD_SUITE/bin/openFPGALoader" -b "$FPGA_BOARD" "$OUTPUTDIR/bitstream.bit" > "$OUTPUTDIR/flash.log" 2>&1
    if [ $? -ne 0 ]; then
        echo "Ask $id: Flashing failed."
        jq --arg id "$id" --rawfile content "$OUTPUTDIR/flash.log" -n -r \
            '{"content": ("```\n" + $content + "\n```"), "medias":[], "tags": "", "privacy": 10, "content_warning": "Flashing failed.", "ask": $id, "mentionedUserIds": []}' \
            > "$OUTPUTDIR/request.json"
        curl --silent -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $WAFRN_TOKEN" -d "@$OUTPUTDIR/request.json" "$WAFRN_URL/api/v3/createPost" > /dev/null
        echo "Finished processing ask $id."
        return 1
    fi

    echo "Ask $id: Recording video..."
    ffmpeg -f v4l2 -framerate 15 -video_size 640x480 -use_wallclock_as_timestamps 1 -i /dev/video0 -pix_fmt yuv420p -ss 5s -t 30s -preset superfast "$OUTPUTDIR/video.mp4"

    echo "Ask $id: Flashing idle bitstream..."
    "$OSS_CAD_SUITE/bin/openFPGALoader" -b "$FPGA_BOARD" "$SCRIPTDIR/idle.bit" > /dev/null
    if [ $? -ne 0 ]; then
        echo "WARNING: Flashing idle bitstream failed!"
    fi

    echo "Ask $id: Uploading video..."
    medias="$(curl --silent -F image="@$OUTPUTDIR/video.mp4" -H "Authorization: Bearer $WAFRN_TOKEN" $WAFRN_URL/api/uploadMedia)"
    media="$(echo "$medias" | jq -r --rawfile code "$INPUTFILE" '.[0] | .description = ("Output of the following VHDL code:\n\n" + $code)')"

    jq --arg id "$id" --argjson media "$media" --rawfile report "$OUTPUTDIR/report.html" -n -r \
        '{"content": ("<b>Sucess!</b>"+$report), "medias":[$media], "tags": "", "privacy": 0, "content_warning": "", "ask": $id, "mentionedUserIds": []}' \
        > "$OUTPUTDIR/request.json"
    curl --silent -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $WAFRN_TOKEN" -d "@$OUTPUTDIR/request.json" "$WAFRN_URL/api/v3/createPost" > /dev/null

    echo "Finished processing ask $id."
}

while true; do
    fetch_asks
    if [ $? -ne 0 ]; then
        echo "No asks."
        sleep $IDLE_DELAY
        continue
    fi

    process_ask
done
rm -r "$WORKDIR"
