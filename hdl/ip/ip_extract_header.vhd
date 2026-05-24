----------------------------------------------------------------------------------
-- Engineer: Mike Field <hamster@snap.net.nz>
--
-- Module Name: ip_extract_header - Behavioral
--
-- Description: Extract the IP header fields. Also verifies the IPv4 header
--              checksum when check_checksum is true; a packet that fails the
--              checksum has data_valid_out held low so downstream handlers
--              never see it.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ip_extract_header is
    generic (
        our_ip         : std_logic_vector(31 downto 0) := (others => '0');
        our_broadcast  : std_logic_vector(31 downto 0) := (others => '0');
        check_checksum : boolean := true);
    Port ( clk                : in  STD_LOGIC;

           data_valid_in      : in  STD_LOGIC;
           data_in            : in  STD_LOGIC_VECTOR (7 downto 0);
           data_valid_out     : out STD_LOGIC := '0';
           data_out           : out STD_LOGIC_VECTOR (7 downto 0)  := (others => '0');

           filter_protocol    : in  STD_LOGIC_VECTOR ( 7 downto 0)  := (others => '0');

           ip_version         : out STD_LOGIC_VECTOR ( 3 downto 0)  := (others => '0');
           ip_type_of_service : out STD_LOGIC_VECTOR ( 7 downto 0)  := (others => '0');
           ip_length          : out STD_LOGIC_VECTOR (15 downto 0)  := (others => '0');
           ip_identification  : out STD_LOGIC_VECTOR (15 downto 0)  := (others => '0');
           ip_flags           : out STD_LOGIC_VECTOR ( 2 downto 0)  := (others => '0');
           ip_fragment_offset : out STD_LOGIC_VECTOR (12 downto 0)  := (others => '0');
           ip_ttl             : out STD_LOGIC_VECTOR ( 7 downto 0)  := (others => '0');
           ip_checksum        : out STD_LOGIC_VECTOR (15 downto 0)  := (others => '0');
           ip_src_ip          : out STD_LOGIC_VECTOR (31 downto 0)  := (others => '0');
           ip_dest_ip         : out STD_LOGIC_VECTOR (31 downto 0)  := (others => '0');
           ip_dest_broadcast  : out STD_LOGIC);
end ip_extract_header;

architecture Behavioral of ip_extract_header is
    signal count          : unsigned(6 downto 0)         := (others => '0');
    signal header_len     : unsigned(6 downto 0)         := (others => '0');

    signal i_ip_version         : STD_LOGIC_VECTOR ( 3 downto 0)  := (others => '0');
    signal i_ip_type_of_service : STD_LOGIC_VECTOR ( 7 downto 0)  := (others => '0');
    signal i_ip_length          : STD_LOGIC_VECTOR (15 downto 0)  := (others => '0');
    signal i_ip_identification  : STD_LOGIC_VECTOR (15 downto 0)  := (others => '0');
    signal i_ip_flags           : STD_LOGIC_VECTOR ( 2 downto 0)  := (others => '0');
    signal i_ip_fragment_offset : STD_LOGIC_VECTOR (12 downto 0)  := (others => '0');
    signal i_ip_ttl             : STD_LOGIC_VECTOR ( 7 downto 0)  := (others => '0');
    signal i_ip_protocol        : STD_LOGIC_VECTOR ( 7 downto 0)  := (others => '0');
    signal i_ip_checksum        : STD_LOGIC_VECTOR (15 downto 0)  := (others => '0');
    signal i_ip_src_ip          : STD_LOGIC_VECTOR (31 downto 0)  := (others => '0');
    signal i_ip_dest_ip         : STD_LOGIC_VECTOR (31 downto 0)  := (others => '0');
    signal data_count           : UNSIGNED(10 downto 0)   := (others => '0');

    -- Running checksum over the IP header. A valid header's ones-complement
    -- sum (including the existing checksum field) folds to 0xFFFF.
    signal sum_acc     : unsigned(31 downto 0) := (others => '0');
    signal sum_hi      : std_logic_vector(7 downto 0) := (others => '0');
    signal checksum_ok : std_logic := '0';
begin

    ip_version         <= i_ip_version;
    ip_type_of_service <= i_ip_type_of_service;
    ip_length          <= i_ip_length;
    ip_identification  <= i_ip_identification;
    ip_flags           <= i_ip_flags;
    ip_fragment_offset <= i_ip_fragment_offset;
    ip_ttl             <= i_ip_ttl;
    ip_checksum        <= i_ip_checksum;
    ip_src_ip          <= i_ip_src_ip;
    ip_dest_ip         <= i_ip_dest_ip;
    ip_dest_broadcast  <= '1' when i_ip_dest_ip = our_broadcast else '0';

process(clk)
    variable v_sum : unsigned(31 downto 0);
    begin
        if rising_edge(clk) then
            data_out <= data_in;
            if data_valid_in = '1' then
                data_count <= data_count + 1;

                -- Pair adjacent header bytes into 16-bit words and sum
                if count = 0 then
                    sum_acc     <= (others => '0');
                    checksum_ok <= '0';
                end if;
                if count(0) = '0' then
                    sum_hi <= data_in;
                else
                    if unsigned(count) < unsigned(header_len) then
                        sum_acc <= sum_acc + unsigned(x"0000" & sum_hi & data_in);
                    end if;
                end if;

                -- When the whole header has just been consumed, fold and check
                if count + 1 = header_len then
                    v_sum := sum_acc + unsigned(x"0000" & sum_hi & data_in);
                    v_sum := ("0000000000000000" & v_sum(31 downto 16)) +
                             ("0000000000000000" & v_sum(15 downto 0));
                    v_sum := ("0000000000000000" & v_sum(31 downto 16)) +
                             ("0000000000000000" & v_sum(15 downto 0));
                    if v_sum(15 downto 0) = x"FFFF" then
                        checksum_ok <= '1';
                    else
                        checksum_ok <= '0';
                    end if;
                end if;

                case count is
                    when "0000000" => i_ip_version                      <= data_in(7 downto 4);
                                      header_len(5 downto 2)            <= unsigned(data_in(3 downto 0));
                    when "0000001" => i_ip_type_of_service              <= data_in;
                    when "0000010" => i_ip_length(15 downto 8)          <= data_in;
                    when "0000011" => i_ip_length( 7 downto 0)          <= data_in;
                    when "0000100" => i_ip_identification(15 downto 8)  <= data_in;
                    when "0000101" => i_ip_identification( 7 downto 0)  <= data_in;
                    when "0000110" => i_ip_fragment_offset(12 downto 8) <= data_in(4 downto 0);
                                      i_ip_flags                        <= data_in(7 downto 5);
                    when "0000111" => i_ip_fragment_offset( 7 downto 0) <= data_in;
                    when "0001000" => i_ip_ttl                          <= data_in;
                    when "0001001" => i_ip_protocol                     <= data_in;
                    when "0001010" => i_ip_checksum(15 downto 8)        <= data_in;
                    when "0001011" => i_ip_checksum( 7 downto 0)        <= data_in;
                    when "0001100" => i_ip_src_ip( 7 downto 0)          <= data_in;
                    when "0001101" => i_ip_src_ip(15 downto 8)          <= data_in;
                    when "0001110" => i_ip_src_ip(23 downto 16)         <= data_in;
                    when "0001111" => i_ip_src_ip(31 downto 24)         <= data_in;
                    when "0010000" => i_ip_dest_ip( 7 downto 0)         <= data_in;
                    when "0010001" => i_ip_dest_ip(15 downto 8)         <= data_in;
                    when "0010010" => i_ip_dest_ip(23 downto 16)        <= data_in;
                    when "0010011" => i_ip_dest_ip(31 downto 24)        <= data_in;
                    when others    => null;
                end case;

                if unsigned(count) >= unsigned(header_len) and unsigned(count) > 4
                    and i_ip_version = x"4" and i_ip_protocol = filter_protocol
                    and (i_ip_dest_ip = our_ip or i_ip_dest_ip = our_broadcast)
                    and (checksum_ok = '1' or not check_checksum) then

                    if data_count < unsigned(i_ip_length) then
                        data_valid_out <= data_valid_in;
                    else
                        data_valid_out <= '0';
                    end if;
                    data_out <= data_in;
                end if;
                if count /= "1111111" then
                    count <= count + 1;
                end if;
            else
               data_valid_out <= '0';
               data_out       <= data_in;
               count          <= (others => '0');
               data_count     <= (others => '0');
               sum_acc        <= (others => '0');
               checksum_ok    <= '0';
            end if;
        end if;
    end process;
end Behavioral;
