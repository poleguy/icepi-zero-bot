library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dvi_out is
    generic(
        h_active : integer := 640;
        h_front_porch : integer := 16;
        h_sync_pulse : integer := 96;
        h_back_porch : integer := 48;

        v_active : integer := 480;
        v_front_porch : integer := 10;
        v_sync_pulse : integer := 2;
        v_back_porch : integer := 33
    );
    port(
        clk_pixel : in std_logic;
        clk_serial : in std_logic;
        rst : in std_logic;

        px : out integer range 0 to h_active - 1;
        py : out integer range 0 to v_active - 1;
        hsync : out std_logic;
        vsync : out std_logic;
        de : out std_logic;

        r : in std_logic_vector(7 downto 0);
        g : in std_logic_vector(7 downto 0);
        b : in std_logic_vector(7 downto 0);

        tmds : out std_logic_vector(3 downto 0)
    );
end dvi_out;

architecture rtl of dvi_out is
    constant total_w : integer := h_active + h_front_porch + h_sync_pulse + h_back_porch;
    constant total_h : integer := v_active + v_front_porch + v_sync_pulse + v_back_porch;

    signal internal_px : integer range 0 to total_w - 1 := 0;
    signal internal_py : integer range 0 to total_h - 1 := 0;

    signal d_r, d_g, d_b : std_logic_vector(7 downto 0);
    signal c_r, c_g, c_b : std_logic_vector(1 downto 0);

    signal t_r, t_g, t_b : std_logic_vector(9 downto 0);
    signal tt_r, tt_g, tt_b : std_logic_vector(9 downto 0);
begin
    -- Pixel Counter
    process(clk_pixel, rst)
    begin
        if rst = '1' then
            internal_px <= 0;
            internal_py <= 0;
        elsif rising_edge(clk_pixel) then
            if internal_px = total_w - 1 then
                internal_px <= 0;
                if internal_py = total_h - 1 then
                    internal_py <= 0;
                else
                    internal_py <= internal_py + 1;
                end if;
            else
                internal_px <= internal_px + 1;
            end if;
        end if;
    end process;

    hsync <= '1' when (internal_px >= h_active + h_front_porch - 1 and internal_px < h_active + h_front_porch + h_sync_pulse - 1) else '0';
    vsync <= '1' when (internal_py >= v_active + v_front_porch - 1 and internal_py < v_active + v_front_porch + v_sync_pulse - 1) else '0';
    de <= '1' when (internal_px < h_active and internal_py < v_active) else '0';
    px <= internal_px when internal_px < h_active else 0;
    py <= internal_py when internal_py < v_active else 0;

    -- Data and Control Generator
    process(clk_pixel)
    begin
        if rising_edge(clk_pixel) then
            d_r <= r when de = '1' else (others => '0');
            d_g <= g when de = '1' else (others => '0');
            d_b <= b when de = '1' else (others => '0');

            c_r <= "00";
            c_g <= "00";
            c_b <= vsync & hsync;
        end if;
    end process;

    -- TMDS Encoder
    tmds_r : entity work.tmds_encoder port map(clk => clk_pixel, rst => rst, data => d_r, ctrl => c_r, de => de, tmds => t_r);
    tmds_g : entity work.tmds_encoder port map(clk => clk_pixel, rst => rst, data => d_g, ctrl => c_g, de => de, tmds => t_g);
    tmds_b : entity work.tmds_encoder port map(clk => clk_pixel, rst => rst, data => d_b, ctrl => c_b, de => de, tmds => t_b);

    -- Serializer
    process(clk_serial)
        variable ser_load : std_logic := '1';
        variable ser_counter : integer range 0 to 9;
    begin
        if rising_edge(clk_serial) then
            tt_r <= t_r when ser_load = '1' else ("0" & tt_r(9 downto 1));
            tt_g <= t_g when ser_load = '1' else ("0" & tt_g(9 downto 1));
            tt_b <= t_b when ser_load = '1' else ("0" & tt_b(9 downto 1));

            ser_load := '1' when ser_counter = 9 else '0';
            ser_counter := 0 when ser_counter = 9 else ser_counter + 1;
        end if;
    end process;

    tmds(0) <= tt_b(0);
    tmds(1) <= tt_g(0);
    tmds(2) <= tt_r(0);
    tmds(3) <= clk_pixel;
end rtl;
