library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.numeric_std_unsigned.all;

-- This module reads and parses the CRT file that is loaded into the HyperRAM device.
-- It stores decoded header information in variours tables.
-- Furthermore, it loads and caches the active banks into BRAM.

-- This module runs entirely in the HyperRAM clock domain, and therefore the BRAM
-- is placed outside this module.

-- It acts as a master towards both the HyperRAM and the BRAM.
-- The maximum amount of addressable HyperRAM is 22 address bits @ 16 data bits, i.e. 8 MB of memory.
-- Not all this memory will be available to the CRT file, though.
-- The CRT file is stored in little-endian format, i.e. even address bytes are in bits 7-0 and
-- odd address bytes are in bits 15-8.

-- req_start_i   : Asserted when the entire CRT file has been loaded verbatim into HyperRAM.
-- req_address_i : The start address in HyperRAM (in units of 16-bit words).
-- req_length_i  : The length of the CRT file (in units of bytes).

-- bank_lo_i and bank_hi_i are in units of 8kB.

entity crt_loader is
   port (
      clk_i               : in  std_logic;
      rst_i               : in  std_logic;

      -- Control interface (QNICE)
      req_start_i         : in  std_logic;
      req_address_i       : in  std_logic_vector(21 downto 0);     -- Address in HyperRAM of start of CRT file
      req_length_i        : in  std_logic_vector(22 downto 0);     -- Length of CRT file in HyperRAM
      resp_status_o       : out std_logic_vector( 3 downto 0);
      resp_error_o        : out std_logic_vector( 3 downto 0);
      resp_address_o      : out std_logic_vector(22 downto 0) := (others => '0');

      -- Control interface (CORE)
      bank_lo_i           : in  std_logic_vector( 6 downto 0);     -- Current location in HyperRAM of bank LO
      bank_hi_i           : in  std_logic_vector( 6 downto 0);     -- Current location in HyperRAM of bank HI

      -- Connect to HyperRAM
      avm_write_o         : out std_logic;
      avm_read_o          : out std_logic;
      avm_address_o       : out std_logic_vector(21 downto 0);
      avm_writedata_o     : out std_logic_vector(15 downto 0);
      avm_byteenable_o    : out std_logic_vector( 1 downto 0);
      avm_burstcount_o    : out std_logic_vector( 7 downto 0);
      avm_readdata_i      : in  std_logic_vector(15 downto 0);
      avm_readdatavalid_i : in  std_logic;
      avm_waitrequest_i   : in  std_logic;

      -- Connect to cartridge.v
      cart_bank_laddr_o   : out std_logic_vector(15 downto 0);     -- bank loading address
      cart_bank_size_o    : out std_logic_vector(15 downto 0);     -- length of each bank
      cart_bank_num_o     : out std_logic_vector(15 downto 0);
      cart_bank_raddr_o   : out std_logic_vector(24 downto 0);     -- chip packet address (low 13 bits are ignored)
      cart_bank_wr_o      : out std_logic;
      cart_loading_o      : out std_logic;
      cart_id_o           : out std_logic_vector(15 downto 0);     -- cart ID or cart type
      cart_exrom_o        : out std_logic_vector( 7 downto 0);     -- CRT file EXROM status
      cart_game_o         : out std_logic_vector( 7 downto 0);     -- CRT file GAME status

      -- Connect to BRAM (2*8kB)
      bram_address_o      : out std_logic_vector(11 downto 0);
      bram_data_o         : out std_logic_vector(15 downto 0);
      bram_lo_wren_o      : out std_logic;
      bram_lo_q_i         : in  std_logic_vector(15 downto 0);
      bram_hi_wren_o      : out std_logic;
      bram_hi_q_i         : in  std_logic_vector(15 downto 0)
   );
end entity crt_loader;

architecture synthesis of crt_loader is

   constant C_STAT_IDLE         : std_logic_vector(3 downto 0) := "0000";
   constant C_STAT_PARSING      : std_logic_vector(3 downto 0) := "0001";
   constant C_STAT_READY        : std_logic_vector(3 downto 0) := "0010"; -- Successfully parsed CRT file
   constant C_STAT_ERROR        : std_logic_vector(3 downto 0) := "0011"; -- Error parsing CRT file

   constant C_ERROR_NONE        : std_logic_vector(3 downto 0) := "0000";
   constant C_ERROR_LEN_SMALL   : std_logic_vector(3 downto 0) := "0001"; -- Length is too small
   constant C_ERROR_CRT_HDR     : std_logic_vector(3 downto 0) := "0010"; -- Missing CRT header
   constant C_ERROR_CHIP_HDR    : std_logic_vector(3 downto 0) := "0011"; -- Missing CHIP header

   subtype R_CRT_FILE_HEADER_LENGTH is natural range  4*8-1 downto  0*8;
   subtype R_CRT_CARTRIDGE_VERSION  is natural range  6*8-1 downto  4*8;
   subtype R_CRT_CARTRIDGE_TYPE     is natural range  8*8-1 downto  6*8;
   subtype R_CRT_EXROM              is natural range  9*8-1 downto  8*8;
   subtype R_CRT_GAME               is natural range 10*8-1 downto  9*8;

   subtype R_CHIP_SIGNATURE         is natural range  4*8-1 downto  0*8;
   subtype R_CHIP_LENGTH            is natural range  8*8-1 downto  4*8;
   subtype R_CHIP_TYPE              is natural range 10*8-1 downto  8*8;
   subtype R_CHIP_BANK_NUMBER       is natural range 12*8-1 downto 10*8;
   subtype R_CHIP_LOAD_ADDRESS      is natural range 14*8-1 downto 12*8;
   subtype R_CHIP_IMAGE_SIZE        is natural range 16*8-1 downto 14*8;

   type t_state is (IDLE_ST,
                    WAIT_FOR_CRT_HEADER_00_ST,
                    WAIT_FOR_CRT_HEADER_10_ST,
                    WAIT_FOR_CHIP_HEADER_ST,
                    READY_ST,
                    READ_HI_ST,
                    READ_LO_ST,
                    ERROR_ST);
   signal state         : t_state := IDLE_ST;

   -- 16-byte of data in little-endian format
   signal wide_readdata : std_logic_vector(127 downto 0);
   signal wide_readdata_valid : std_logic;
   signal read_pos      : integer range 0 to 7;

   signal req_address   : std_logic_vector(21 downto 0);
   signal base_address  : std_logic_vector(21 downto 0);
   signal end_address   : std_logic_vector(21 downto 0);

   signal bank_lo_d     : std_logic_vector(6 downto 0);
   signal bank_hi_d     : std_logic_vector(6 downto 0);
   signal hi_load       : std_logic;
   signal hi_load_done  : std_logic;
   signal lo_load       : std_logic;
   signal lo_load_done  : std_logic;

   -- Convert an ASCII string to std_logic_vector (little-endian format)
   pure function str2slv(s : string) return std_logic_vector is
      variable res : std_logic_vector(s'length*8-1 downto 0);
   begin
      for i in 0 to s'length-1 loop
         res(8*i+7 downto 8*i) := to_stdlogicvector(character'pos(s(i+1)), 8);
      end loop;
      return res;
   end function str2slv;

   -- purpose: byteswap a vector
   pure function bswap (din : std_logic_vector) return std_logic_vector is
      variable swapped : std_logic_vector(din'length-1 downto 0);
      variable input   : std_logic_vector(din'length-1 downto 0);
   begin  -- function bswap
      -- normalize din to start at zero and to have downto as direction
      for i in 0 to din'length-1 loop
         input(i) := din(i+din'low);
      end loop;  -- i
      for i in 0 to din'length/8-1 loop
         swapped(swapped'high-i*8 downto swapped'high-i*8-7) := input(i*8+7 downto i*8);
      end loop;  -- i
      return swapped;
   end function bswap;

--attribute mark_debug : string;
--attribute mark_debug of start_i             : signal is "true";
--attribute mark_debug of address_i           : signal is "true";
--attribute mark_debug of bank_lo_i           : signal is "true";
--attribute mark_debug of bank_hi_i           : signal is "true";
--attribute mark_debug of avm_write_o         : signal is "true";
--attribute mark_debug of avm_read_o          : signal is "true";
--attribute mark_debug of avm_address_o       : signal is "true";
--attribute mark_debug of avm_writedata_o     : signal is "true";
--attribute mark_debug of avm_byteenable_o    : signal is "true";
--attribute mark_debug of avm_burstcount_o    : signal is "true";
--attribute mark_debug of avm_readdata_i      : signal is "true";
--attribute mark_debug of avm_readdatavalid_i : signal is "true";
--attribute mark_debug of avm_waitrequest_i   : signal is "true";
--attribute mark_debug of cart_bank_laddr_o   : signal is "true";
--attribute mark_debug of cart_bank_size_o    : signal is "true";
--attribute mark_debug of cart_bank_num_o     : signal is "true";
--attribute mark_debug of cart_bank_raddr_o   : signal is "true";
--attribute mark_debug of cart_bank_wr_o      : signal is "true";
--attribute mark_debug of cart_loading_o      : signal is "true";
--attribute mark_debug of cart_id_o           : signal is "true";
--attribute mark_debug of cart_exrom_o        : signal is "true";
--attribute mark_debug of cart_game_o         : signal is "true";
--attribute mark_debug of bram_address_o      : signal is "true";
--attribute mark_debug of bram_data_o         : signal is "true";
--attribute mark_debug of bram_lo_wren_o      : signal is "true";
--attribute mark_debug of bram_lo_q_i         : signal is "true";
--attribute mark_debug of bram_hi_wren_o      : signal is "true";
--attribute mark_debug of bram_hi_q_i         : signal is "true";
--attribute mark_debug of state               : signal is "true";
--attribute mark_debug of hi_load             : signal is "true";
--attribute mark_debug of hi_load_done        : signal is "true";
--attribute mark_debug of lo_load             : signal is "true";
--attribute mark_debug of lo_load_done        : signal is "true";

begin

   -- Signal to the CORE when the CRT file is successfully parsed and ready.
   cart_loading_o <= '0' when state = IDLE_ST or
                              state = ERROR_ST or
                             (state = READY_ST and lo_load = '0' and hi_load = '0') else
                     '1';

   p_fsm : process (clk_i)
      variable file_header_length_v : std_logic_vector(31 downto 0);
      variable image_size_v         : std_logic_vector(15 downto 0);
      variable read_addr_v          : std_logic_vector(21 downto 0);
      variable offset_v             : natural;
   begin
      if rising_edge(clk_i) then
         cart_bank_wr_o <= '0';
         bram_lo_wren_o <= '0';
         bram_hi_wren_o <= '0';
         hi_load_done   <= '0';
         lo_load_done   <= '0';
         wide_readdata_valid <= '0';

         if avm_waitrequest_i = '0' then
            avm_write_o <= '0';
            avm_read_o  <= '0';
         end if;

         -- Gather together 16 bytes of data.
         -- This is just to make the following state machine simpler,
         -- i.e. we can process more data at a time.
         if avm_readdatavalid_i = '1' then
            wide_readdata(16*read_pos + 15 downto 16*read_pos) <= avm_readdata_i;

            if read_pos = 7 then
               wide_readdata_valid <= '1'; -- 16 bytes are now ready
               read_pos <= 0;
            else
               read_pos <= read_pos + 1;
            end if;
         end if;

         case state is
            when IDLE_ST =>
               if req_start_i = '1' then
                  req_address <= req_address_i;
                  -- As a minimum, the file must contain a complete CRT header.
                  if req_length_i >= X"00040" then
                     -- Read first 0x20 bytes of CRT header.
                     avm_address_o    <= req_address_i;
                     avm_read_o       <= '1';
                     avm_burstcount_o <= X"10";
                     end_address      <= req_address_i + req_length_i(22 downto 1);
                     resp_status_o    <= C_STAT_PARSING;
                     state            <= WAIT_FOR_CRT_HEADER_00_ST;
                  else
                     resp_status_o  <= C_STAT_ERROR;
                     resp_error_o   <= C_ERROR_LEN_SMALL;
                     resp_address_o <= (others => '0');
                     state          <= ERROR_ST;
                  end if;
               end if;

            when WAIT_FOR_CRT_HEADER_00_ST =>
               if wide_readdata_valid = '1' then
                  if wide_readdata = str2slv("C64 CARTRIDGE   ") then
                     state <= WAIT_FOR_CRT_HEADER_10_ST;
                  else
                     resp_status_o  <= C_STAT_ERROR;
                     resp_error_o   <= C_ERROR_CRT_HDR;
                     resp_address_o(22 downto 1) <= avm_address_o - req_address;
                     state          <= ERROR_ST;
                  end if;
               end if;

            when WAIT_FOR_CRT_HEADER_10_ST =>
               if wide_readdata_valid = '1' then
                  cart_id_o    <= bswap(wide_readdata(R_CRT_CARTRIDGE_TYPE));
                  cart_exrom_o <= wide_readdata(R_CRT_EXROM);
                  cart_game_o  <= wide_readdata(R_CRT_GAME);
                  file_header_length_v := bswap(wide_readdata(R_CRT_FILE_HEADER_LENGTH));

                  if req_length_i >= file_header_length_v(22 downto 1) + X"10" then
                     -- Read 0x10 bytes from CHIP header
                     avm_address_o    <= avm_address_o + file_header_length_v(22 downto 1);
                     avm_read_o       <= '1';
                     avm_burstcount_o <= X"08";
                     base_address     <= avm_address_o + file_header_length_v(22 downto 1) + X"08";
                     state <= WAIT_FOR_CHIP_HEADER_ST;
                  else
                     resp_status_o  <= C_STAT_ERROR;
                     resp_error_o   <= C_ERROR_LEN_SMALL;
                     resp_address_o(22 downto 1) <= avm_address_o - req_address;
                     state          <= ERROR_ST;
                  end if;
               end if;

            when WAIT_FOR_CHIP_HEADER_ST =>
               if wide_readdata_valid = '1' then
                  if wide_readdata(R_CHIP_SIGNATURE) = str2slv("CHIP") then
                     cart_bank_laddr_o <= bswap(wide_readdata(R_CHIP_LOAD_ADDRESS));
                     cart_bank_size_o  <= bswap(wide_readdata(R_CHIP_IMAGE_SIZE));
                     cart_bank_num_o   <= bswap(wide_readdata(R_CHIP_BANK_NUMBER));
                     read_addr_v := avm_address_o + X"08";
                     cart_bank_raddr_o <= (others => '0');
                     cart_bank_raddr_o(22 downto 1) <= read_addr_v - base_address;
                     cart_bank_wr_o    <= '1';

                     -- OK, assume we're done now
                     resp_status_o    <= C_STAT_READY;
                     state            <= READY_ST;

                     image_size_v := bswap(wide_readdata(R_CHIP_IMAGE_SIZE));
                     if end_address >= avm_address_o + X"08" + image_size_v(15 downto 1) + X"08" then
                        -- Oh, there's more ...
                        avm_address_o    <= avm_address_o + X"08" + image_size_v(15 downto 1);
                        avm_read_o       <= '1';
                        avm_burstcount_o <= X"08";
                        resp_status_o    <= C_STAT_PARSING;
                        state            <= WAIT_FOR_CHIP_HEADER_ST;
                     end if;
                  else
                     resp_status_o  <= C_STAT_ERROR;
                     resp_error_o   <= C_ERROR_LEN_SMALL;
                     resp_address_o(22 downto 1) <= avm_address_o - req_address;
                     state          <= ERROR_ST;
                  end if;
               end if;

            when READY_ST =>
               if hi_load = '1' and hi_load_done = '0' then
                  -- Starting load to HI bank
                  avm_write_o        <= '0';
                  avm_read_o         <= '1';
                  offset_v := 16#1008# * to_integer(bank_hi_i);
                  avm_address_o      <= base_address + offset_v;
                  avm_burstcount_o   <= X"80"; -- Read 256 bytes
                  bram_address_o     <= (others => '1');
                  state              <= READ_HI_ST;
               elsif lo_load = '1' and lo_load_done = '0' then
                  -- Starting load to LO bank
                  avm_write_o        <= '0';
                  avm_read_o         <= '1';
                  offset_v := 16#1008# * to_integer(bank_lo_i);
                  avm_address_o      <= base_address + offset_v;
                  avm_burstcount_o   <= X"80"; -- Read 256 bytes
                  bram_address_o     <= (others => '1');
                  state              <= READ_LO_ST;
               end if;

            when READ_HI_ST =>
               if avm_readdatavalid_i = '1' then
                  bram_data_o    <= avm_readdata_i;
                  bram_hi_wren_o <= '1';
                  bram_address_o <= bram_address_o + 1;
                  if bram_address_o = X"FFE" then
                     hi_load_done <= '1';
                     state        <= READY_ST;
                  elsif bram_address_o(6 downto 0) = X"7E" then
                     avm_write_o      <= '0';
                     avm_read_o       <= '1';
                     avm_address_o    <= avm_address_o + X"80";
                     avm_burstcount_o <= X"80"; -- Read 256 bytes
                  end if;
               end if;

            when READ_LO_ST =>
               if avm_readdatavalid_i = '1' then
                  bram_data_o    <= avm_readdata_i;
                  bram_lo_wren_o <= '1';
                  bram_address_o <= bram_address_o + 1;
                  if bram_address_o = X"FFE" then
                     lo_load_done <= '1';
                     state        <= READY_ST;
                  elsif bram_address_o(6 downto 0) = X"7E" then
                     avm_write_o      <= '0';
                     avm_read_o       <= '1';
                     avm_address_o    <= avm_address_o + X"80";
                     avm_burstcount_o <= X"80"; -- Read 256 bytes
                  end if;
               end if;

            when ERROR_ST =>
               if req_start_i = '0' then
                  resp_status_o  <= C_STAT_IDLE;
                  resp_error_o   <= C_ERROR_NONE;
                  resp_address_o <= (others => '0');
                  state          <= IDLE_ST;
               end if;

            when others =>
               null;
         end case;

         if rst_i = '1' then
            avm_write_o         <= '0';
            avm_read_o          <= '0';
            avm_address_o       <= (others => '0');
            avm_writedata_o     <= (others => '0');
            avm_byteenable_o    <= (others => '0');
            avm_burstcount_o    <= (others => '0');
            bram_address_o      <= (others => '0');
            bram_data_o         <= (others => '0');
            bram_lo_wren_o      <= '0';
            bram_hi_wren_o      <= '0';
            cart_bank_raddr_o   <= (others => '0');
            cart_bank_wr_o      <= '0';
            cart_id_o           <= (others => '0');
            cart_exrom_o        <= (others => '1');
            cart_game_o         <= (others => '1');
            resp_status_o       <= C_STAT_IDLE;
            resp_error_o        <= C_ERROR_NONE;
            resp_address_o      <= (others => '0');
            state               <= IDLE_ST;
            read_pos            <= 0;
            wide_readdata_valid <= '0';
            req_address         <= (others => '0');
         end if;

      end if;
   end process p_fsm;

   p_crt_load : process (clk_i)
   begin
      if rising_edge(clk_i) then
         bank_lo_d  <= bank_lo_i;
         bank_hi_d  <= bank_hi_i;
         if lo_load_done = '1' then
            lo_load <= '0';
         end if;
         if hi_load_done = '1' then
            hi_load <= '0';
         end if;

         -- Detect change in bank addresses
         if bank_lo_d /= bank_lo_i then
            lo_load <= '1';
         end if;
         if bank_hi_d /= bank_hi_i then
            hi_load <= '1';
         end if;

         -- Force cache of the LO bank immediately after parsing CRT file.
         if state = WAIT_FOR_CHIP_HEADER_ST then
            lo_load <= '1';
         end if;

         if rst_i = '1' or state = IDLE_ST then
            lo_load <= '0';
            hi_load <= '0';
         end if;
      end if;
   end process p_crt_load;

end architecture synthesis;
