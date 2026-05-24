----------------------------------------------------------------------------------
-- net_pkg - networking helpers for self-checking testbenches
--
-- Types
--   byte_array_t : unconstrained array of bytes
--
-- Helpers
--   ip_checksum         : RFC 1071 ones-complement Internet checksum
--   ip_to_wire          : convert byte-reversed-storage IP to network order
--   mac_to_wire         : convert byte-reversed-storage MAC to network order
--   make_arp_request    : raw Ethernet frame containing an ARP request
--   make_icmp_echo      : raw Ethernet frame containing an ICMP echo request
--
-- All make_* helpers prepend the 8-byte Ethernet preamble + SFD and append a
-- 4-byte placeholder FCS (the DUT does not currently validate FCS).
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package net_pkg is

    type byte_array_t is array(natural range <>) of std_logic_vector(7 downto 0);

    constant ETH_PREAMBLE : byte_array_t(0 to 7) :=
        (x"55", x"55", x"55", x"55", x"55", x"55", x"55", x"D5");

    function ip_checksum(buf : byte_array_t) return std_logic_vector;

    -- IEEE 802.3 Ethernet CRC32 (polynomial 0xEDB88320, reflected, init/xor 0xFFFFFFFF).
    -- Returns the 4-byte FCS as it appears on the wire (LSB-first byte order).
    function eth_crc32(buf : byte_array_t) return byte_array_t;

    -- Compute and append FCS to frame_bytes(eth_start..pad_end-1), writing it
    -- into the last 4 byte positions. Convenience helper for make_* builders.
    procedure attach_fcs(variable frame : inout byte_array_t;
                         constant eth_start : in integer;
                         constant fcs_start : in integer);

    function make_arp_request(
        sender_mac : std_logic_vector(47 downto 0);
        sender_ip  : std_logic_vector(31 downto 0);
        target_ip  : std_logic_vector(31 downto 0)
    ) return byte_array_t;

    function make_icmp_echo(
        sender_mac : std_logic_vector(47 downto 0);
        sender_ip  : std_logic_vector(31 downto 0);
        dut_mac    : std_logic_vector(47 downto 0);
        dut_ip     : std_logic_vector(31 downto 0);
        ident      : std_logic_vector(15 downto 0);
        seq        : std_logic_vector(15 downto 0);
        payload    : byte_array_t
    ) return byte_array_t;

    function make_udp(
        sender_mac : std_logic_vector(47 downto 0);
        sender_ip  : std_logic_vector(31 downto 0);
        dut_mac    : std_logic_vector(47 downto 0);
        dut_ip     : std_logic_vector(31 downto 0);
        src_port   : std_logic_vector(15 downto 0);
        dst_port   : std_logic_vector(15 downto 0);
        payload    : byte_array_t
    ) return byte_array_t;

    -- TCP flag bit positions in the 1-byte flags field at TCP header offset 13
    constant TCP_FIN : std_logic_vector(7 downto 0) := x"01";
    constant TCP_SYN : std_logic_vector(7 downto 0) := x"02";
    constant TCP_RST : std_logic_vector(7 downto 0) := x"04";
    constant TCP_PSH : std_logic_vector(7 downto 0) := x"08";
    constant TCP_ACK : std_logic_vector(7 downto 0) := x"10";

    function make_tcp(
        sender_mac : std_logic_vector(47 downto 0);
        sender_ip  : std_logic_vector(31 downto 0);
        dut_mac    : std_logic_vector(47 downto 0);
        dut_ip     : std_logic_vector(31 downto 0);
        src_port   : std_logic_vector(15 downto 0);
        dst_port   : std_logic_vector(15 downto 0);
        seq_num    : std_logic_vector(31 downto 0);
        ack_num    : std_logic_vector(31 downto 0);
        flags      : std_logic_vector(7 downto 0);
        window     : std_logic_vector(15 downto 0);
        payload    : byte_array_t
    ) return byte_array_t;

end package net_pkg;

package body net_pkg is

    function ip_checksum(buf : byte_array_t) return std_logic_vector is
        variable sum  : unsigned(31 downto 0) := (others => '0');
        variable word : unsigned(15 downto 0);
        variable i    : integer := buf'low;
    begin
        while i <= buf'high loop
            if i = buf'high then
                word := unsigned(buf(i)) & x"00";
            else
                word := unsigned(buf(i)) & unsigned(buf(i + 1));
            end if;
            sum := sum + word;
            i := i + 2;
        end loop;
        while sum(31 downto 16) /= 0 loop
            sum := ("0000000000000000" & sum(31 downto 16)) +
                   ("0000000000000000" & sum(15 downto 0));
        end loop;
        return std_logic_vector(not sum(15 downto 0));
    end function;

    function eth_crc32(buf : byte_array_t) return byte_array_t is
        variable crc  : unsigned(31 downto 0) := (others => '1');
        variable b    : unsigned(7 downto 0);
        variable bit0 : std_logic;
        variable out_buf : byte_array_t(0 to 3);
    begin
        for i in buf'low to buf'high loop
            b := unsigned(buf(i));
            crc := crc xor (x"000000" & b);
            for k in 0 to 7 loop
                bit0 := crc(0);
                crc := "0" & crc(31 downto 1);
                if bit0 = '1' then
                    crc := crc xor x"EDB88320";
                end if;
            end loop;
        end loop;
        crc := crc xor x"FFFFFFFF";
        -- FCS goes on the wire LSB-first
        out_buf(0) := std_logic_vector(crc( 7 downto  0));
        out_buf(1) := std_logic_vector(crc(15 downto  8));
        out_buf(2) := std_logic_vector(crc(23 downto 16));
        out_buf(3) := std_logic_vector(crc(31 downto 24));
        return out_buf;
    end function;

    procedure attach_fcs(variable frame : inout byte_array_t;
                         constant eth_start : in integer;
                         constant fcs_start : in integer) is
        variable payload_view : byte_array_t(0 to fcs_start - eth_start - 1);
        variable fcs          : byte_array_t(0 to 3);
    begin
        for i in 0 to payload_view'high loop
            payload_view(i) := frame(eth_start + i);
        end loop;
        fcs := eth_crc32(payload_view);
        for i in 0 to 3 loop
            frame(fcs_start + i) := fcs(i);
        end loop;
    end procedure;

    function make_arp_request(
        sender_mac : std_logic_vector(47 downto 0);
        sender_ip  : std_logic_vector(31 downto 0);
        target_ip  : std_logic_vector(31 downto 0)
    ) return byte_array_t is
        variable f : byte_array_t(0 to 71) := (others => x"00");
    begin
        f(0 to 7) := ETH_PREAMBLE;
        -- Eth dst MAC = broadcast
        f(8 to 13) := (x"FF", x"FF", x"FF", x"FF", x"FF", x"FF");
        for i in 0 to 5 loop
            f(14 + i) := sender_mac(47 - i*8 downto 40 - i*8);
        end loop;
        f(20) := x"08"; f(21) := x"06";          -- EtherType ARP
        f(22) := x"00"; f(23) := x"01";          -- HW Ethernet
        f(24) := x"08"; f(25) := x"00";          -- Proto IPv4
        f(26) := x"06"; f(27) := x"04";          -- HW len, proto len
        f(28) := x"00"; f(29) := x"01";          -- Operation = request
        for i in 0 to 5 loop
            f(30 + i) := sender_mac(47 - i*8 downto 40 - i*8);
        end loop;
        for i in 0 to 3 loop
            f(36 + i) := sender_ip(31 - i*8 downto 24 - i*8);
        end loop;
        f(40 to 45) := (x"00", x"00", x"00", x"00", x"00", x"00");
        for i in 0 to 3 loop
            f(46 + i) := target_ip(31 - i*8 downto 24 - i*8);
        end loop;
        -- Compute proper FCS over the frame body (after 8-byte preamble, before FCS)
        attach_fcs(f, 8, 68);
        return f;
    end function;

    function make_icmp_echo(
        sender_mac : std_logic_vector(47 downto 0);
        sender_ip  : std_logic_vector(31 downto 0);
        dut_mac    : std_logic_vector(47 downto 0);
        dut_ip     : std_logic_vector(31 downto 0);
        ident      : std_logic_vector(15 downto 0);
        seq        : std_logic_vector(15 downto 0);
        payload    : byte_array_t
    ) return byte_array_t is
        constant pl_len   : integer := payload'length;
        constant icmp_len : integer := 8 + pl_len;       -- ICMP header (8) + payload
        constant ip_len   : integer := 20 + icmp_len;    -- IP header (20) + ICMP
        constant eth_len  : integer := 14 + ip_len;      -- Eth header (14) + IP
        -- Pad to 46-byte minimum Ethernet payload; with our typical ping
        -- payload of >= 18 bytes no padding is needed.
        function max0(x : integer) return integer is
        begin
            if x > 0 then return x; else return 0; end if;
        end;
        constant pad_bytes   : integer := max0(46 - ip_len);
        constant frame_bytes : integer := eth_len + pad_bytes + 4;  -- + FCS
        constant total       : integer := 8 + frame_bytes;          -- + preamble
        variable f : byte_array_t(0 to total - 1) := (others => x"00");

        variable ip_buf   : byte_array_t(0 to 19);
        variable icmp_buf : byte_array_t(0 to icmp_len - 1);
        variable ck       : std_logic_vector(15 downto 0);
        variable ip_len_v : std_logic_vector(15 downto 0);
    begin
        f(0 to 7) := ETH_PREAMBLE;
        -- dst MAC = dut_mac
        for i in 0 to 5 loop
            f(8 + i) := dut_mac(47 - i*8 downto 40 - i*8);
        end loop;
        -- src MAC
        for i in 0 to 5 loop
            f(14 + i) := sender_mac(47 - i*8 downto 40 - i*8);
        end loop;
        -- EtherType IPv4
        f(20) := x"08"; f(21) := x"00";

        -- Build ICMP message (header + payload), compute checksum
        icmp_buf := (others => x"00");
        icmp_buf(0) := x"08";       -- Type 8 = echo request
        icmp_buf(1) := x"00";       -- Code 0
        icmp_buf(2) := x"00";       -- checksum hi (placeholder)
        icmp_buf(3) := x"00";       -- checksum lo
        icmp_buf(4) := ident(15 downto 8);
        icmp_buf(5) := ident( 7 downto 0);
        icmp_buf(6) := seq(15 downto 8);
        icmp_buf(7) := seq( 7 downto 0);
        for i in 0 to pl_len - 1 loop
            icmp_buf(8 + i) := payload(payload'low + i);
        end loop;
        ck := ip_checksum(icmp_buf);
        icmp_buf(2) := ck(15 downto 8);
        icmp_buf(3) := ck( 7 downto 0);

        -- Build IP header
        ip_len_v := std_logic_vector(to_unsigned(ip_len, 16));
        ip_buf(0)  := x"45";           -- Version 4, IHL 5
        ip_buf(1)  := x"00";           -- TOS
        ip_buf(2)  := ip_len_v(15 downto 8);
        ip_buf(3)  := ip_len_v( 7 downto 0);
        ip_buf(4)  := x"00"; ip_buf(5) := x"01";   -- Ident
        ip_buf(6)  := x"00"; ip_buf(7) := x"00";   -- Flags + frag offset
        ip_buf(8)  := x"40";           -- TTL 64
        ip_buf(9)  := x"01";           -- Protocol ICMP
        ip_buf(10) := x"00"; ip_buf(11) := x"00";  -- checksum (placeholder)
        for i in 0 to 3 loop
            ip_buf(12 + i) := sender_ip(31 - i*8 downto 24 - i*8);
        end loop;
        for i in 0 to 3 loop
            ip_buf(16 + i) := dut_ip(31 - i*8 downto 24 - i*8);
        end loop;
        ck := ip_checksum(ip_buf);
        ip_buf(10) := ck(15 downto 8);
        ip_buf(11) := ck( 7 downto 0);

        -- Splice into frame
        for i in 0 to 19 loop
            f(22 + i) := ip_buf(i);
        end loop;
        for i in 0 to icmp_len - 1 loop
            f(42 + i) := icmp_buf(i);
        end loop;
        -- Proper Ethernet FCS over bytes 8..total-5 (preamble excluded, FCS slot last 4)
        attach_fcs(f, 8, total - 4);
        return f;
    end function;

    function make_udp(
        sender_mac : std_logic_vector(47 downto 0);
        sender_ip  : std_logic_vector(31 downto 0);
        dut_mac    : std_logic_vector(47 downto 0);
        dut_ip     : std_logic_vector(31 downto 0);
        src_port   : std_logic_vector(15 downto 0);
        dst_port   : std_logic_vector(15 downto 0);
        payload    : byte_array_t
    ) return byte_array_t is
        constant pl_len   : integer := payload'length;
        constant udp_len  : integer := 8 + pl_len;       -- UDP hdr + data
        constant ip_len   : integer := 20 + udp_len;     -- IP hdr + UDP
        constant eth_len  : integer := 14 + ip_len;
        function max0(x : integer) return integer is
        begin
            if x > 0 then return x; else return 0; end if;
        end;
        constant pad_bytes   : integer := max0(46 - ip_len);
        constant frame_bytes : integer := eth_len + pad_bytes + 4;
        constant total       : integer := 8 + frame_bytes;
        variable f         : byte_array_t(0 to total - 1) := (others => x"00");
        variable ip_buf    : byte_array_t(0 to 19);
        variable ck        : std_logic_vector(15 downto 0);
        variable ip_len_v  : std_logic_vector(15 downto 0);
        variable udp_len_v : std_logic_vector(15 downto 0);
    begin
        f(0 to 7) := ETH_PREAMBLE;
        for i in 0 to 5 loop
            f(8 + i)  := dut_mac(47 - i*8 downto 40 - i*8);
            f(14 + i) := sender_mac(47 - i*8 downto 40 - i*8);
        end loop;
        f(20) := x"08"; f(21) := x"00";   -- IPv4

        -- IP header
        ip_len_v := std_logic_vector(to_unsigned(ip_len, 16));
        ip_buf(0)  := x"45";
        ip_buf(1)  := x"00";
        ip_buf(2)  := ip_len_v(15 downto 8);
        ip_buf(3)  := ip_len_v( 7 downto 0);
        ip_buf(4)  := x"00"; ip_buf(5) := x"02";
        ip_buf(6)  := x"00"; ip_buf(7) := x"00";
        ip_buf(8)  := x"40";
        ip_buf(9)  := x"11";              -- Protocol UDP
        ip_buf(10) := x"00"; ip_buf(11) := x"00";
        for i in 0 to 3 loop
            ip_buf(12 + i) := sender_ip(31 - i*8 downto 24 - i*8);
            ip_buf(16 + i) := dut_ip(31 - i*8 downto 24 - i*8);
        end loop;
        ck := ip_checksum(ip_buf);
        ip_buf(10) := ck(15 downto 8);
        ip_buf(11) := ck( 7 downto 0);
        for i in 0 to 19 loop
            f(22 + i) := ip_buf(i);
        end loop;

        -- UDP header + payload (UDP checksum left at zero - permitted in IPv4)
        udp_len_v := std_logic_vector(to_unsigned(udp_len, 16));
        f(42) := src_port(15 downto 8);
        f(43) := src_port( 7 downto 0);
        f(44) := dst_port(15 downto 8);
        f(45) := dst_port( 7 downto 0);
        f(46) := udp_len_v(15 downto 8);
        f(47) := udp_len_v( 7 downto 0);
        f(48) := x"00"; f(49) := x"00";   -- UDP checksum zero
        for i in 0 to pl_len - 1 loop
            f(50 + i) := payload(payload'low + i);
        end loop;

        attach_fcs(f, 8, total - 4);
        return f;
    end function;

    function make_tcp(
        sender_mac : std_logic_vector(47 downto 0);
        sender_ip  : std_logic_vector(31 downto 0);
        dut_mac    : std_logic_vector(47 downto 0);
        dut_ip     : std_logic_vector(31 downto 0);
        src_port   : std_logic_vector(15 downto 0);
        dst_port   : std_logic_vector(15 downto 0);
        seq_num    : std_logic_vector(31 downto 0);
        ack_num    : std_logic_vector(31 downto 0);
        flags      : std_logic_vector(7 downto 0);
        window     : std_logic_vector(15 downto 0);
        payload    : byte_array_t
    ) return byte_array_t is
        constant pl_len  : integer := payload'length;
        constant tcp_len : integer := 20 + pl_len;      -- TCP hdr + data
        constant ip_len  : integer := 20 + tcp_len;
        constant eth_len : integer := 14 + ip_len;
        function max0(x : integer) return integer is
        begin
            if x > 0 then return x; else return 0; end if;
        end;
        constant pad_bytes   : integer := max0(46 - ip_len);
        constant frame_bytes : integer := eth_len + pad_bytes + 4;
        constant total       : integer := 8 + frame_bytes;
        variable f         : byte_array_t(0 to total - 1) := (others => x"00");
        variable ip_buf    : byte_array_t(0 to 19);
        variable tcp_pseudo : byte_array_t(0 to 11 + tcp_len);  -- 12-byte pseudo + TCP
        variable ck        : std_logic_vector(15 downto 0);
        variable ip_len_v  : std_logic_vector(15 downto 0);
        variable tcp_len_v : std_logic_vector(15 downto 0);
    begin
        f(0 to 7) := ETH_PREAMBLE;
        for i in 0 to 5 loop
            f(8 + i)  := dut_mac(47 - i*8 downto 40 - i*8);
            f(14 + i) := sender_mac(47 - i*8 downto 40 - i*8);
        end loop;
        f(20) := x"08"; f(21) := x"00";   -- IPv4

        ip_len_v := std_logic_vector(to_unsigned(ip_len, 16));
        ip_buf(0)  := x"45";
        ip_buf(1)  := x"00";
        ip_buf(2)  := ip_len_v(15 downto 8);
        ip_buf(3)  := ip_len_v( 7 downto 0);
        ip_buf(4)  := x"00"; ip_buf(5) := x"03";
        ip_buf(6)  := x"00"; ip_buf(7) := x"00";
        ip_buf(8)  := x"40";
        ip_buf(9)  := x"06";              -- Protocol TCP
        ip_buf(10) := x"00"; ip_buf(11) := x"00";
        for i in 0 to 3 loop
            ip_buf(12 + i) := sender_ip(31 - i*8 downto 24 - i*8);
            ip_buf(16 + i) := dut_ip(31 - i*8 downto 24 - i*8);
        end loop;
        ck := ip_checksum(ip_buf);
        ip_buf(10) := ck(15 downto 8);
        ip_buf(11) := ck( 7 downto 0);
        for i in 0 to 19 loop
            f(22 + i) := ip_buf(i);
        end loop;

        -- TCP header into f(42..61) and payload into f(62..)
        f(42) := src_port(15 downto 8);
        f(43) := src_port( 7 downto 0);
        f(44) := dst_port(15 downto 8);
        f(45) := dst_port( 7 downto 0);
        for i in 0 to 3 loop
            f(46 + i) := seq_num(31 - i*8 downto 24 - i*8);
            f(50 + i) := ack_num(31 - i*8 downto 24 - i*8);
        end loop;
        f(54) := x"50";          -- Data offset 5 (no options), reserved
        f(55) := flags;
        f(56) := window(15 downto 8);
        f(57) := window( 7 downto 0);
        f(58) := x"00"; f(59) := x"00";  -- checksum (placeholder)
        f(60) := x"00"; f(61) := x"00";  -- urgent pointer
        for i in 0 to pl_len - 1 loop
            f(62 + i) := payload(payload'low + i);
        end loop;

        -- TCP checksum = ones-complement over pseudo header + TCP segment
        tcp_len_v := std_logic_vector(to_unsigned(tcp_len, 16));
        for i in 0 to 3 loop
            tcp_pseudo(i)     := sender_ip(31 - i*8 downto 24 - i*8);
            tcp_pseudo(4 + i) := dut_ip(31 - i*8 downto 24 - i*8);
        end loop;
        tcp_pseudo(8)  := x"00";
        tcp_pseudo(9)  := x"06";   -- protocol TCP
        tcp_pseudo(10) := tcp_len_v(15 downto 8);
        tcp_pseudo(11) := tcp_len_v( 7 downto 0);
        for i in 0 to tcp_len - 1 loop
            tcp_pseudo(12 + i) := f(42 + i);
        end loop;
        ck := ip_checksum(tcp_pseudo);
        f(58) := ck(15 downto 8);
        f(59) := ck( 7 downto 0);

        attach_fcs(f, 8, total - 4);
        return f;
    end function;

end package body net_pkg;
