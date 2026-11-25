-------------------------------------------------------------------------------
-- FILE NAME   : ram2ddr_fixed.vhd
-- ENTITY      : ram2ddr   (drop-in replacement for Digilent's ram2ddr.vhd,
--                          the variant WITHOUT internal XADC)
-- BASED ON    : Digilent ram2ddr.vhd v1.0 (Mihaita Nagy, 2014)
--
-- Simple asynchronous-SRAM-style interface to the Nexys 4 DDR / A7 DDR2 via
-- the Xilinx MIG ("ddr" IP: DDR2, 3333 ps, 2:1, x16, BL8, native interface).
--
-- Fixes vs. the original wrapper:
--   1. app_addr/app_cmd/write data are latched BEFORE app_en is raised
--      (original raised app_en one cycle early -> extra command to the
--      previous address on every access).
--   2. app_en is held only until accepted (app_en & app_rdy) and
--      app_wdf_wren only until accepted (app_wdf_wren & app_wdf_rdy)
--      (original kept them high while waiting -> duplicate commands / extra
--      write-data beats whenever the MIG was busy, e.g. during refresh).
--   3. In 2:1 mode a BL8 burst needs TWO 64-bit write beats (app_wdf_end on
--      the 2nd); both are now sent, with the unused beat fully masked.
--   4. Reads wait for both returned beats and take the word from the right one.
--   5. Inputs pass through a 2-flop synchronizer into the MIG ui_clk domain.
--   6. Full 128 MiB address space is used (original used only half of each
--      burst).
--
-- Interface (unchanged):
--   ram_a    : BYTE address (bit 0 ignored for 16-bit accesses)
--   READ     : CEN=0, OEN=0, WEN=1  ->  data on ram_dq_o when done
--   WRITE    : CEN=0, WEN=0, OEN=1  ->  ram_dq_i written
--   UB/LB    : active-low byte enables (both low = 16-bit access)
--   Address/data must be stable >= ~20 ns before CEN falls and while CEN is
--   low. CEN must go high for >= ~30 ns between accesses.
--
-- New optional outputs (may be left unconnected):
--   calib_o   : MIG calibration complete
--   ram_ack_o : '1' once the current access has completed; stays '1' until
--               CEN goes high. (ui_clk domain -> synchronize with 2 flops in
--               your clock domain before using.) Use it instead of fixed
--               wait times for a fully reliable handshake.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity ram2ddr is
   port (
      -- Common
      clk_200MHz_i         : in    std_logic; -- 200 MHz system clock
      rst_i                : in    std_logic; -- active high system reset
      device_temp_i        : in    std_logic_vector(11 downto 0);

      -- RAM interface
      ram_a                : in    std_logic_vector(26 downto 0);
      ram_dq_i             : in    std_logic_vector(15 downto 0);
      ram_dq_o             : out   std_logic_vector(15 downto 0);
      ram_cen              : in    std_logic;
      ram_oen              : in    std_logic;
      ram_wen              : in    std_logic;
      ram_ub               : in    std_logic;
      ram_lb               : in    std_logic;

      -- Optional status (new)
      calib_o              : out   std_logic;
      ram_ack_o            : out   std_logic;

      -- DDR2 interface
      ddr2_addr            : out   std_logic_vector(12 downto 0);
      ddr2_ba              : out   std_logic_vector(2 downto 0);
      ddr2_ras_n           : out   std_logic;
      ddr2_cas_n           : out   std_logic;
      ddr2_we_n            : out   std_logic;
      ddr2_ck_p            : out   std_logic_vector(0 downto 0);
      ddr2_ck_n            : out   std_logic_vector(0 downto 0);
      ddr2_cke             : out   std_logic_vector(0 downto 0);
      ddr2_cs_n            : out   std_logic_vector(0 downto 0);
      ddr2_dm              : out   std_logic_vector(1 downto 0);
      ddr2_odt             : out   std_logic_vector(0 downto 0);
      ddr2_dq              : inout std_logic_vector(15 downto 0);
      ddr2_dqs_p           : inout std_logic_vector(1 downto 0);
      ddr2_dqs_n           : inout std_logic_vector(1 downto 0)
   );
end ram2ddr;

architecture Behavioral of ram2ddr is

------------------------------------------------------------------------
-- MIG component (native interface, 2:1, x16)
------------------------------------------------------------------------
component ddr
   port (
      ddr2_dq              : inout std_logic_vector(15 downto 0);
      ddr2_dqs_p           : inout std_logic_vector(1 downto 0);
      ddr2_dqs_n           : inout std_logic_vector(1 downto 0);
      ddr2_addr            : out   std_logic_vector(12 downto 0);
      ddr2_ba              : out   std_logic_vector(2 downto 0);
      ddr2_ras_n           : out   std_logic;
      ddr2_cas_n           : out   std_logic;
      ddr2_we_n            : out   std_logic;
      ddr2_ck_p            : out   std_logic_vector(0 downto 0);
      ddr2_ck_n            : out   std_logic_vector(0 downto 0);
      ddr2_cke             : out   std_logic_vector(0 downto 0);
      ddr2_cs_n            : out   std_logic_vector(0 downto 0);
      ddr2_dm              : out   std_logic_vector(1 downto 0);
      ddr2_odt             : out   std_logic_vector(0 downto 0);
      sys_clk_i            : in    std_logic;
      clk_ref_i            : in    std_logic;
      sys_rst              : in    std_logic;
      app_addr             : in    std_logic_vector(26 downto 0);
      app_cmd              : in    std_logic_vector(2 downto 0);
      app_en               : in    std_logic;
      app_wdf_data         : in    std_logic_vector(63 downto 0);
      app_wdf_end          : in    std_logic;
      app_wdf_mask         : in    std_logic_vector(7 downto 0);
      app_wdf_wren         : in    std_logic;
      app_rd_data          : out   std_logic_vector(63 downto 0);
      app_rd_data_end      : out   std_logic;
      app_rd_data_valid    : out   std_logic;
      app_rdy              : out   std_logic;
      app_wdf_rdy          : out   std_logic;
      app_sr_req           : in    std_logic;
      app_sr_active        : out   std_logic;
      app_ref_req          : in    std_logic;
      app_ref_ack          : out   std_logic;
      app_zq_req           : in    std_logic;
      app_zq_ack           : out   std_logic;
      ui_clk               : out   std_logic;
      ui_clk_sync_rst      : out   std_logic;
      device_temp_i        : in    std_logic_vector(11 downto 0);
      init_calib_complete  : out   std_logic);
end component;

------------------------------------------------------------------------
-- Types / constants
------------------------------------------------------------------------
type state_type is (stIdle, stWrD0, stWrD1, stWrCmd, stRdCmd, stRdWait, stWaitCen);

constant CMD_WRITE : std_logic_vector(2 downto 0) := "000";
constant CMD_READ  : std_logic_vector(2 downto 0) := "001";

------------------------------------------------------------------------
-- Signals
------------------------------------------------------------------------
signal state                     : state_type := stIdle;

signal mem_ui_clk                : std_logic;
signal mem_ui_rst                : std_logic;
signal rstn                      : std_logic;
signal rst_s1, rst_s2            : std_logic := '1';
signal rst                       : std_logic;

-- input synchronizer bus:
--   47..21 = ram_a, 20..5 = ram_dq_i, 4 = cen, 3 = oen, 2 = wen, 1 = ub, 0 = lb
signal in_bus                    : std_logic_vector(47 downto 0);
signal in_s1, in_s2              : std_logic_vector(47 downto 0) := (others => '1');

-- latched request
signal a_r                       : std_logic_vector(26 downto 0) := (others => '0');
signal d_r                       : std_logic_vector(15 downto 0) := (others => '0');
signal ub_r, lb_r                : std_logic := '0';
signal rd_beat                   : std_logic := '0';
signal ack_r                     : std_logic := '0';

-- write masks for the two beats of a burst
signal mask_b0, mask_b1          : std_logic_vector(7 downto 0);

-- MIG user interface
signal mem_addr                  : std_logic_vector(26 downto 0);
signal mem_cmd                   : std_logic_vector(2 downto 0);
signal mem_en                    : std_logic;
signal mem_rdy                   : std_logic;
signal mem_wdf_rdy               : std_logic;
signal mem_wdf_data              : std_logic_vector(63 downto 0);
signal mem_wdf_end               : std_logic;
signal mem_wdf_mask              : std_logic_vector(7 downto 0);
signal mem_wdf_wren              : std_logic;
signal mem_rd_data               : std_logic_vector(63 downto 0);
signal mem_rd_data_end           : std_logic;
signal mem_rd_data_valid         : std_logic;
signal mem_init_calib_complete   : std_logic;

begin

------------------------------------------------------------------------
-- MIG instance
------------------------------------------------------------------------
   Inst_DDR: ddr
   port map (
      ddr2_dq              => ddr2_dq,
      ddr2_dqs_p           => ddr2_dqs_p,
      ddr2_dqs_n           => ddr2_dqs_n,
      ddr2_addr            => ddr2_addr,
      ddr2_ba              => ddr2_ba,
      ddr2_ras_n           => ddr2_ras_n,
      ddr2_cas_n           => ddr2_cas_n,
      ddr2_we_n            => ddr2_we_n,
      ddr2_ck_p            => ddr2_ck_p,
      ddr2_ck_n            => ddr2_ck_n,
      ddr2_cke             => ddr2_cke,
      ddr2_cs_n            => ddr2_cs_n,
      ddr2_dm              => ddr2_dm,
      ddr2_odt             => ddr2_odt,
      sys_clk_i            => clk_200MHz_i,
      clk_ref_i            => clk_200MHz_i,
      sys_rst              => rstn,             -- MIG reset is ACTIVE LOW
      app_addr             => mem_addr,
      app_cmd              => mem_cmd,
      app_en               => mem_en,
      app_wdf_data         => mem_wdf_data,
      app_wdf_end          => mem_wdf_end,
      app_wdf_mask         => mem_wdf_mask,
      app_wdf_wren         => mem_wdf_wren,
      app_rd_data          => mem_rd_data,
      app_rd_data_end      => mem_rd_data_end,
      app_rd_data_valid    => mem_rd_data_valid,
      app_rdy              => mem_rdy,
      app_wdf_rdy          => mem_wdf_rdy,
      app_sr_req           => '0',
      app_sr_active        => open,
      app_ref_req          => '0',
      app_ref_ack          => open,
      app_zq_req           => '0',
      app_zq_ack           => open,
      ui_clk               => mem_ui_clk,
      ui_clk_sync_rst      => mem_ui_rst,
      device_temp_i        => device_temp_i,
      init_calib_complete  => mem_init_calib_complete);

   rstn      <= not rst_i;
   calib_o   <= mem_init_calib_complete;
   ram_ack_o <= ack_r;

------------------------------------------------------------------------
-- Synchronize the asynchronous user-side inputs into ui_clk (2 flops)
------------------------------------------------------------------------
   in_bus <= ram_a & ram_dq_i & ram_cen & ram_oen & ram_wen & ram_ub & ram_lb;

   SYNC_IN: process(mem_ui_clk)
   begin
      if rising_edge(mem_ui_clk) then
         in_s1  <= in_bus;
         in_s2  <= in_s1;
         rst_s1 <= rst_i;
         rst_s2 <= rst_s1;
      end if;
   end process SYNC_IN;

   rst <= rst_s2 or mem_ui_rst;

------------------------------------------------------------------------
-- MIG handshake outputs, decoded directly from the state so they are
-- asserted exactly while waiting and drop on the accepting clock edge
------------------------------------------------------------------------
   -- app_addr is in 16-bit word units; a BL8 burst covers 8 words = 16 bytes
   mem_addr     <= '0' & a_r(26 downto 4) & "000";
   mem_cmd      <= CMD_READ when state = stRdCmd else CMD_WRITE;
   mem_en       <= '1' when (state = stWrCmd or state = stRdCmd) else '0';
   mem_wdf_wren <= '1' when (state = stWrD0 or state = stWrD1) else '0';
   mem_wdf_end  <= '1' when state = stWrD1 else '0';
   mem_wdf_data <= d_r & d_r & d_r & d_r;            -- word replicated; mask picks one
   mem_wdf_mask <= mask_b1 when state = stWrD1 else mask_b0;

------------------------------------------------------------------------
-- Byte masks (mask bit = '1' -> byte NOT written)
--   a_r(3)      selects the beat (words 0-3 or 4-7 of the burst)
--   a_r(2 downto 1) selects the word inside the beat
------------------------------------------------------------------------
   MASK: process(a_r, ub_r, lb_r)
      variable m : std_logic_vector(7 downto 0);
   begin
      m := (others => '1');
      case a_r(2 downto 1) is
         when "00"   => m(1) := ub_r; m(0) := lb_r;
         when "01"   => m(3) := ub_r; m(2) := lb_r;
         when "10"   => m(5) := ub_r; m(4) := lb_r;
         when others => m(7) := ub_r; m(6) := lb_r;
      end case;
      if a_r(3) = '0' then
         mask_b0 <= m;
         mask_b1 <= (others => '1');
      else
         mask_b0 <= (others => '1');
         mask_b1 <= m;
      end if;
   end process MASK;

------------------------------------------------------------------------
-- Control FSM (ui_clk domain)
------------------------------------------------------------------------
   FSM: process(mem_ui_clk)
      variable w : std_logic_vector(15 downto 0);
   begin
      if rising_edge(mem_ui_clk) then
         if rst = '1' then
            state    <= stIdle;
            ack_r    <= '0';
            rd_beat  <= '0';
            ram_dq_o <= (others => '0');
         else
            case state is

               when stIdle =>
                  ack_r <= '0';
                  -- new access: calibrated and CEN low
                  if mem_init_calib_complete = '1' and in_s2(4) = '0' then
                     a_r  <= in_s2(47 downto 21);
                     d_r  <= in_s2(20 downto 5);
                     ub_r <= in_s2(1);
                     lb_r <= in_s2(0);
                     if in_s2(2) = '0' then          -- WEN low -> write
                        state <= stWrD0;
                     elsif in_s2(3) = '0' then       -- OEN low -> read
                        rd_beat <= '0';
                        state   <= stRdCmd;
                     end if;
                  end if;

               -- ---------------- write: 2 data beats, then the command
               when stWrD0 =>
                  if mem_wdf_rdy = '1' then state <= stWrD1; end if;

               when stWrD1 =>
                  if mem_wdf_rdy = '1' then state <= stWrCmd; end if;

               when stWrCmd =>
                  if mem_rdy = '1' then state <= stWaitCen; end if;

               -- ---------------- read: command, then 2 returned beats
               when stRdCmd =>
                  if mem_rdy = '1' then state <= stRdWait; end if;

               when stRdWait =>
                  if mem_rd_data_valid = '1' then
                     if rd_beat = a_r(3) then        -- the beat holding our word
                        case a_r(2 downto 1) is
                           when "00"   => w := mem_rd_data(15 downto 0);
                           when "01"   => w := mem_rd_data(31 downto 16);
                           when "10"   => w := mem_rd_data(47 downto 32);
                           when others => w := mem_rd_data(63 downto 48);
                        end case;
                        if ub_r = '0' and lb_r = '1' then      -- upper byte only
                           ram_dq_o <= w(15 downto 8) & w(15 downto 8);
                        elsif ub_r = '1' and lb_r = '0' then   -- lower byte only
                           ram_dq_o <= w(7 downto 0) & w(7 downto 0);
                        else                                   -- 16-bit
                           ram_dq_o <= w;
                        end if;
                     end if;
                     if rd_beat = '1' then
                        state <= stWaitCen;
                     end if;
                     rd_beat <= not rd_beat;
                  end if;

               -- ---------------- done: hold ack until the user releases CEN
               when stWaitCen =>
                  ack_r <= '1';
                  if in_s2(4) = '1' then
                     state <= stIdle;
                  end if;

               when others =>
                  state <= stIdle;
            end case;
         end if;
      end if;
   end process FSM;

end Behavioral;
