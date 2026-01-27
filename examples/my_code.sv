module my_code #(
    parameter int WIDTH = 640,
    parameter int HEIGHT = 480,
    parameter int CONSOLE_COLUMNS = WIDTH / 8,
    parameter int CONSOLE_ROWS = HEIGHT / 8
)(
    input  logic clk,
    input  logic rst,

    input  int px,
    input  int py,
    input  logic hsync,
    input  logic vsync,

    input  int col,
    input  int row,

    output int char,
    output logic [23:0] foreground_color,
    output logic [23:0] background_color
);
    logic [31:0] frame_counter = '0;
    logic old_vsync = '0;

    logic [7:0] red, green, blue;

    always_comb begin
        red   = 8'(col * 4);
        green = 8'(py);
        blue  = frame_counter[7:0];

        background_color = {red, green, blue};
        foreground_color = '1;

        char = 0;
    end

    always_ff @(posedge clk) begin
        if (vsync == 1'b0 && old_vsync == 1'b1) begin
            frame_counter <= frame_counter + 1;
        end
        
        old_vsync <= vsync;
    end
endmodule
