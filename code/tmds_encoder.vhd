library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tmds_encoder is
    port(
        clk : in std_logic;
        rst : in std_logic;

        data : in std_logic_vector(7 downto 0);
        ctrl : in std_logic_vector(1 downto 0);
        de : in std_logic;

        tmds : out std_logic_vector(9 downto 0)
    );
end tmds_encoder;

architecture rtl of tmds_encoder is
    signal cnt : integer range -128 to 127 := 0;

    function count_ones(input : std_logic_vector) return integer is
        variable count : integer := 0;
    begin
        for i in input'range loop
            if input(i) = '1' then
                count := count + 1;
            end if;
        end loop;
        return count;
    end function;

    function count_zeros(input : std_logic_vector) return integer is
        variable count : integer := 0;
    begin
        for i in input'range loop
            if input(i) = '0' then
                count := count + 1;
            end if;
        end loop;
        return count;
    end function;
begin
    process(clk, rst)
        variable q_m : std_logic_vector(8 downto 0);
        variable N1_d : integer;
        variable N1_q_m : integer;
        variable N0_q_m : integer;
    begin
        if rst = '1' then
            tmds <= (others => '0');
            cnt <= 0;
        elsif rising_edge(clk) then
            N1_d := count_ones(data);

            q_m(0) := data(0);
            if N1_d > 4 or (N1_d = 4 and data(0) = '0') then
                q_m(1) := data(1) xnor q_m(0);
                q_m(2) := data(2) xnor q_m(1);
                q_m(3) := data(3) xnor q_m(2);
                q_m(4) := data(4) xnor q_m(3);
                q_m(5) := data(5) xnor q_m(4);
                q_m(6) := data(6) xnor q_m(5);
                q_m(7) := data(7) xnor q_m(6);
                q_m(8) := '0';
            else
                q_m(1) := data(1) xor q_m(0);
                q_m(2) := data(2) xor q_m(1);
                q_m(3) := data(3) xor q_m(2);
                q_m(4) := data(4) xor q_m(3);
                q_m(5) := data(5) xor q_m(4);
                q_m(6) := data(6) xor q_m(5);
                q_m(7) := data(7) xor q_m(6);
                q_m(8) := '1';
            end if;

            if de = '1' then
                N0_q_m := count_zeros(q_m(7 downto 0));
                N1_q_m := count_ones(q_m(7 downto 0));

                if cnt = 0 or N0_q_m = N1_q_m then
                    tmds(9) <= not q_m(8);
                    tmds(8) <= q_m(8);
                    tmds(7 downto 0) <= q_m(7 downto 0) when q_m(8) = '1' else not q_m(7 downto 0);

                    if q_m(8) = '0' then
                        cnt <= cnt + (N0_q_m - N1_q_m);
                    else
                        cnt <= cnt + (N1_q_m - N0_q_m);
                    end if;
                else
                    if (cnt > 0 and N1_q_m > N0_q_m) or (cnt < 0 and N0_q_m > N1_q_m) then
                        tmds(9) <= '1';
                        tmds(8) <= q_m(8);
                        tmds(7 downto 0) <= not q_m(7 downto 0);
                        cnt <= cnt + (N0_q_m - N1_q_m) + 2 * to_integer(unsigned(q_m(8 downto 8)));
                    else
                        tmds(9) <= '0';
                        tmds(8) <= q_m(8);
                        tmds(7 downto 0) <= q_m(7 downto 0);
                        cnt <= cnt + (N1_q_m - N0_q_m) - 2 * to_integer(unsigned(not q_m(8 downto 8)));
                    end if;
                end if;
            else
                cnt <= 0;
                case ctrl is
                    when "00" =>
                        tmds <= "1101010100";
                    when "01" =>
                        tmds <= "0010101011";
                    when "10" =>
                        tmds <= "0101010100";
                    when others =>
                        tmds <= "1010101011";
                end case;
            end if;
        end if;
    end process;
end rtl;
