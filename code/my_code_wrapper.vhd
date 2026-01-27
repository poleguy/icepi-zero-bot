library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity my_code_wrapper is
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
end my_code_wrapper;

architecture rtl of my_code_wrapper is
    component my_code is
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
begin
    real_inst : my_code
        generic map (
            WIDTH => WIDTH,
            HEIGHT => HEIGHT,
            CONSOLE_COLUMNS => CONSOLE_COLUMNS,
            CONSOLE_ROWS => CONSOLE_ROWS
        )
        port map (
            clk => clk,
            rst => rst,
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
end architecture;
