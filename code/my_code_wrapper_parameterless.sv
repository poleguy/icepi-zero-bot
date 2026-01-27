module my_code_wrapper #(
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
    my_code code_inst (
        .clk, .rst,
        .px, .py, .hsync, .vsync, .col, .row,
        .char, .foreground_color, .background_color
    );
endmodule
