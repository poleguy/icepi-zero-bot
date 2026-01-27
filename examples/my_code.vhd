library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity my_code is
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
end my_code;

architecture rtl of my_code is
    alias red   : std_logic_vector(7 downto 0) is background_color(23 downto 16);
    alias green : std_logic_vector(7 downto 0) is background_color(15 downto 8);
    alias blue  : std_logic_vector(7 downto 0) is background_color(7 downto 0);

    signal frame_counter : unsigned(31 downto 0) := (others => '0');

    constant example_text : string(1 to 19) := "Hello Fediverse! <3";
    constant example_text_row : integer := 15;
    constant example_text_col : integer := 15;
begin
    char <= character'pos(example_text(col + 1 - example_text_col))
        when col >= example_text_col and col < example_text'length + example_text_col and row = example_text_row else 0;

    red   <= std_logic_vector(to_unsigned(col*4, 8));
    green <= std_logic_vector(to_unsigned(py, 8));
    blue  <= std_logic_vector(resize(frame_counter, 8));

    foreground_color <= (others => '1');

    process(clk)
        variable old_vsync : std_logic := '0';
    begin
        if rising_edge(clk) then
            if vsync = '0' and old_vsync = '1' then
                frame_counter <= frame_counter + 1; 
            end if;
            old_vsync := vsync;
        end if;
    end process;
end architecture;
