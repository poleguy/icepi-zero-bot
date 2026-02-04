#!/bin/bash

FPGA_BOARD=icepi-zero
FPGA_PACKAGE=CABGA256
OSS_CAD_SUITE=/opt/oss-cad-suite
IDLE_DELAY=30
TAGS="FPGA, Icepi Zero, HDL"

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

    # Optional expected message count from !ask hint
    EXPECTED_COUNT="$(jq -r '.asks[0].content' "$WORKDIR/asks.json" \
                         | grep -oE '!ask[[:space:]]+[0-9]+' \
                             | awk '{print $2}')"
    if [[ "$EXPECTED_COUNT" =~ ^[0-9]+$ ]]; then
        echo "Ask $id: expecting $EXPECTED_COUNT messages"
    else
        EXPECTED_COUNT=""
    fi

    THREAD_CONTENT=""
    PREV_TEXT=""
    SLEEP=2
    MAX_SLEEP=20

    for attempt in $(seq 1 12); do
        THREAD_JSON="$WORKDIR/$id/context_$attempt.json"

        curl --silent -H "Authorization: Bearer $WAFRN_TOKEN" \
             "$WAFRN_URL/api/v1/statuses/$inReplyTo/context" > "$THREAD_JSON"
        if [ $? -ne 0 ]; then
            echo "Ask $id: context fetch failed, attempt $attempt"
            sleep "$SLEEP"
            continue
        fi

        THREAD_CONTENT="$(jq -r \
      '                      (.ancestors + .descendants)
                                    | sort_by(.created_at)
                                    | map(.content)' "$THREAD_JSON")"

        COUNT="$(echo "$THREAD_CONTENT" | jq 'length')"
        TEXT="$(echo "$THREAD_CONTENT" | jq -r 'join("\n")')"


        # Success: reached expected count
        if [ -n "$EXPECTED_COUNT" ] && [ "$COUNT" -ge "$EXPECTED_COUNT" ]; then
            echo "Ask $id: got $COUNT messages (>= expected $EXPECTED_COUNT)"
            break
        fi

        # If a count hint exists, do NOT accept stability early
        if [ -n "$EXPECTED_COUNT" ]; then
            echo "Ask $id: $COUNT / $EXPECTED_COUNT seen, waiting..."
        else
            # No hint: allow stability exit
            if [ "$TEXT" == "$PREV_TEXT" ]; then
                echo "Ask $id: thread stabilized at $COUNT messages"
                break
            fi
        fi

        PREV_TEXT="$TEXT"

        echo "Ask $id: only $COUNT messages, retrying in ${SLEEP}s..."
        sleep "$SLEEP"

        # Exponential backoff
        if [ "$SLEEP" -lt "$MAX_SLEEP" ]; then
            SLEEP=$(( SLEEP * 2 ))
            [ "$SLEEP" -gt "$MAX_SLEEP" ] && SLEEP="$MAX_SLEEP"
        fi
    done

    echo "$TEXT" > "$INPUTFILE"
    echo "Ask $id: fetched thread with $COUNT messages"
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
                > "$ASKDIR/request.json"
            curl --silent -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $WAFRN_TOKEN" -d "@$ASKDIR/request.json" "$WAFRN_URL/api/v3/createPost" > /dev/null
            echo "Finished processing ask $id."
            return 1
        fi
    fi

    echo "Ask $id: Running synthesis..."
    podman run --rm -a=stdout -a=stderr --network=none \
        -v "$OUTPUTDIR:/output" -v "$SCRIPTDIR/code:/code:ro" \
        -v "$INPUTFILE:/input/message.txt:ro" -v "$SCRIPTDIR/scripts:/scripts:ro" \
        -v "$OSS_CAD_SUITE:/opt/oss-cad-suite/:ro" \
        -v "$HOME/.cargo/bin/spade:/opt/spade/bin/spade:ro" \
        -e FPGA_PACKAGE="$FPGA_PACKAGE" \
        --env-merge PATH='${PATH}:/opt/oss-cad-suite/bin:/opt/spade/bin' \
        icepi-zero-bot-synth-container:latest \
        /scripts/synth.sh /input/message.txt /output /code > "$ASKDIR/synth.log" 2>&1

    if [ $? -ne 0 ]; then
        echo "Ask $id: Synthesis failed."
        jq --arg id "$id" --rawfile content "$ASKDIR/synth.log" -n -r \
            '{"content": ("```\n" + $content + "\n```"), "medias":[], "tags": "", "privacy": 10, "content_warning": "Synthesis failed.", "ask": $id, "mentionedUserIds": []}' \
            > "$ASKDIR/request.json"
        curl --silent -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $WAFRN_TOKEN" -d "@$ASKDIR/request.json" "$WAFRN_URL/api/v3/createPost" > /dev/null
        echo "Finished processing ask $id."
        return 1
    fi

    echo "<details><summary>Utilization</summary><table><thead><th><td><b>Cell</b></td><td><b>Used</b></td><td><b>Available</b></td><td><b>Usage</b></td></th></thead><tbody>" > "$ASKDIR/utilization.html"
    jq -r '.utilization | to_entries[] | select(.value.used > 0) | "<tr><td><code>\(.key)</code></td><td>\(.value.used)</td><td>\(.value.available)</td><td>\(1000*.value.used / .value.available | round/10)%</td></tr>"' "$OUTPUTDIR/report.json" >> "$ASKDIR/utilization.html"
    echo "</tbody></table></details>" >> "$ASKDIR/utilization.html"

    echo "<details><summary>Timing</summary><table><thead><th><td><b>Clock</b></td><td><b>Achieved</b></td><td><b>Constraint</b></td></th></thead><tbody>" > "$ASKDIR/timing.html"
    jq -r '.fmax | to_entries[] | "<tr><td><code>\(.key)</code></td><td>\(.value.achieved*100 | round/100) MHz</td><td>\(.value.constraint*100 | round/100) MHz</td></tr>"' "$OUTPUTDIR/report.json" >> "$ASKDIR/timing.html"
    echo "</tbody></table></details>" >> "$ASKDIR/timing.html"

    cat "$ASKDIR/utilization.html" "$ASKDIR/timing.html" > "$ASKDIR/report.html"

    echo "Ask $id: Flashing bitstream..."
    "$OSS_CAD_SUITE/bin/openFPGALoader" -b "$FPGA_BOARD" "$OUTPUTDIR/bitstream.bit" > "$ASKDIR/flash.log" 2>&1
    if [ $? -ne 0 ]; then
        echo "Ask $id: Flashing failed."
        jq --arg id "$id" --rawfile content "$ASKDIR/flash.log" -n -r \
            '{"content": ("```\n" + $content + "\n```"), "medias":[], "tags": "", "privacy": 10, "content_warning": "Flashing failed.", "ask": $id, "mentionedUserIds": []}' \
            > "$ASKDIR/request.json"
        curl --silent -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $WAFRN_TOKEN" -d "@$ASKDIR/request.json" "$WAFRN_URL/api/v3/createPost" > /dev/null
        echo "Finished processing ask $id."
        return 1
    fi

    echo "Ask $id: Recording video..."
    ffmpeg -f v4l2 -framerate 15 -video_size 640x480 -use_wallclock_as_timestamps 1 -i /dev/video0 -pix_fmt yuv420p -ss 5s -t 30s -preset superfast "$ASKDIR/video.mp4"

    echo "Ask $id: Flashing idle bitstream..."
    "$OSS_CAD_SUITE/bin/openFPGALoader" -b "$FPGA_BOARD" "$SCRIPTDIR/idle.bit" > /dev/null
    if [ $? -ne 0 ]; then
        echo "WARNING: Flashing idle bitstream failed!"
    fi

    echo "Ask $id: Uploading video..."
    medias="$(curl --silent -F image="@$ASKDIR/video.mp4" -H "Authorization: Bearer $WAFRN_TOKEN" $WAFRN_URL/api/uploadMedia)"
    media="$(echo "$medias" | jq -r --rawfile code "$INPUTFILE" '.[0] | .description = ("Output of the following VHDL code:\n\n" + $code)')"

    jq --arg id "$id" --argjson media "$media" --rawfile report "$ASKDIR/report.html" --arg tags "$TAGS" --rawfile hdl "$OUTPUTDIR/hdl.txt" -n -r \
        '{"content": ("<b>Sucess!</b>"+$report), "medias":[$media], "tags": ($tags + ", " + $hdl), "privacy": 0, "content_warning": "", "ask": $id, "mentionedUserIds": []}' \
        > "$ASKDIR/request.json"
    curl --silent -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $WAFRN_TOKEN" -d "@$ASKDIR/request.json" "$WAFRN_URL/api/v3/createPost" > /dev/null

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
