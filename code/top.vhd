library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top is
    port (
        clk : in std_logic;
        led : out std_logic_vector(4 downto 0);
        gpdi_dp : out std_logic_vector(3 downto 0)
    );
end top;

architecture rtl of top is
    component pll is
    port(
        clk_in : in std_logic;
        clkt : out std_logic;
        clkp : out std_logic;
        locked : out std_logic
    );
    end component;

    component my_code_wrapper is
        generic(
            WIDTH : integer := 640;
            HEIGHT : integer := 480;
            CONSOLE_COLUMNS : integer := WIDTH / 8;
            CONSOLE_ROWS : integer := HEIGHT / 8
        );
        port(
            clk : in std_logic;
            rst : in std_logic;

            px : in integer range 0 to WIDTH - 1;
            py : in integer range 0 to HEIGHT - 1;
            hsync : in std_logic;
            vsync : in std_logic;

            col : in integer range 0 to CONSOLE_COLUMNS - 1;
            row : in integer range 0 to CONSOLE_ROWS - 1;

            char : out integer range 0 to 127 := 0;
            foreground_color : out std_logic_vector(23 downto 0) := (others => '0');
            background_color : out std_logic_vector(23 downto 0) := (others => '1')
        );
    end component;

    signal clkp, clkt, clkp_inv : std_logic;
    signal locked : std_logic;

    signal r, g, b : std_logic_vector(7 downto 0);
    signal px : integer range 0 to 639;
    signal py : integer range 0 to 479;
    signal hsync, vsync, de : std_logic;

    signal col : integer range 0 to 640 / 8 - 1;
    signal row : integer range 0 to 480 / 8 - 1;

    signal char : integer range 0 to 127;
    signal foreground_color : std_logic_vector(23 downto 0);
    signal background_color : std_logic_vector(23 downto 0);
begin
    led <= (others => '0');

    pll_inst : pll
        port map(
            clk_in => clk,
            clkp => clkp,
            clkt => clkt,
            locked => locked
        );

    dvi_out_inst : entity work.dvi_out
        port map(
            clk_pixel => clkp,
            clk_serial => clkt,
            rst => not locked,
            hsync => hsync,
            vsync => vsync,
            de => de,
            px => px,
            py => py,
            r => r,
            g => g,
            b => b,
            tmds => gpdi_dp
        );

    console_inst : entity work.console
        port map(
            px => px,
            py => py,
            col => col,
            row => row,
            char => char,
            foreground_color => foreground_color,
            background_color => background_color,
            value => open,
            red => r,
            green => g,
            blue => b
        );

    code_inst : my_code_wrapper
        generic map (
            WIDTH => 640,
            HEIGHT => 480,
            CONSOLE_COLUMNS => 640 / 8,
            CONSOLE_ROWS => 480 / 8
        )
        port map (
            clk => clkp,
            rst => not locked,
            px => px,
            py => py,
            hsync => hsync,
            vsync => vsync,
            col => col,
            row => row,
            char => char,
            foreground_color => foreground_color,
            background_color => background_color
        );
end rtl;
