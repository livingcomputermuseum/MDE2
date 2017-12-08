-- -----------------------------------------------------------------------
-- Massbus Disk Emulator2 Rev A Top Level
-- Bruce Sherry
-- Vulcan, Inc. Living Computer Museum
-- Created 11/6/2013 12:28:29 PM
-- Version: 2.02
-- Date: 3/28/2014 2:02:57 PM

-- 0.00         First version to SVN. BS 10/10/2013 9:08:42 AM
-- 0.00 -> 0.01 Getting Drive select bits correct. BS 10/21/2013 10:36:06 AM
-- 0.01 -> 1.00 Stolen from UPETopMDI.vhd BS 11/6/2013 12:28:39 PM
-- 1.00 -> 2.00 Update to Eric's new Driver/Receiver card. BS 3/5/2014 7:05:41 AM
-- 2.00 -> 2.01 Demand is inverted somehow. BS 3/13/2014 12:50:32 PM
-- 2.01 -> 2.02 RUN and EXC are inverted too. BS 3/28/2014 2:02:57 PM
-- -----------------------------------------------------------------------/

library IEEE;
use IEEE.std_logic_1164.all;  -- defines std_logic types
use IEEE.std_logic_ARITH.ALL;
use IEEE.std_logic_UNSIGNED.ALL;
--use work.IDROMConst.all;
--use work.i22_1000card.all;            -- needs 5i22.ucf and SP3 1000K 320 pin
-- 96 I/O pinouts for 5I22:
--use work.PIN_SV16_96.all;

entity MDE2aTop is  -- for 5I22 PCI9054 based card
        port
    (
        RESET: in std_logic;
        LCLK: in std_logic;

     -- bus interface signals --
        LW_R: in std_logic;
        ADS: in std_logic;
        BLAST: in std_logic;
        READY: out std_logic;
        BTERM: out std_logic;
        INT: out std_logic;
        DREQ: out std_logic;
        HOLD: in std_logic;
        HOLDA: inout std_logic;
        CCS: out std_logic;
        DISABLECONF: out std_logic;

        LAD: inout std_logic_vector (31 downto 0);      -- data/address bus
        LBE: in std_logic_vector (3 downto 0);          -- byte enables

        IOBITS: inout std_logic_vector (95 downto 0);   -- external I/O bits

        -- led bits
        LEDS: out std_logic_vector(7 downto 0)
        );
end MDE2aTop;

architecture dataflow of MDE2aTop is

    component MDE is  -- for 5I22 PCI9054 based card
        port
        (
        RESET: in std_logic;
        LCLK: in std_logic;

         -- bus interface signals --
        LW_R: in std_logic;
        ADS: in std_logic;
        BLAST: in std_logic;
        READY: out std_logic;
        BTERM: out std_logic;
        INT: out std_logic;
        DREQ: out std_logic;
        HOLD: in std_logic;
        HOLDA: inout std_logic;
        CCS: out std_logic;
        DISABLECONF: out std_logic;

        LAD: inout std_logic_vector (31 downto 0);      -- data/address bus
        LBE: in std_logic_vector (3 downto 0);          -- byte enables

    --  These signals will connect to the 5i22 IOBITS

        IEL_DRVH1: out std_logic;                       -- Data Bus Drive Enable 1
        IEL_DRVH2: out std_logic;                       -- Data Bus Drive Enable 2
        RECV_DRV_CNTL: out std_logic;                   -- Read control bus
        CNTRL_BUS_ENABLE: out std_logic;                -- Control Bus Drive Enable
        MB_D: inout std_logic_vector(17 downto 0);      -- Massbus Data Bus
        MB_DPA: inout std_logic;                        -- Massbus Data Parity
        MB_C: inout std_logic_vector(15 downto 0);      -- Massbus Control Bus
        MB_CPA: inout std_logic;                        -- Massbus Control Parity
        MB_SCLK: out std_logic;                         -- Massbus Data Sync Clock
        MB_WCLK: in std_logic;                          -- Massbus Data Write Clock
        MB_RS: in std_logic_vector(4 downto 0);         -- Massbus Register Select
        MB_DS: in std_logic_vector(2 downto 0);         -- Massbus Drive Select
        MB_ATTN: out std_logic;                         -- Massbus Attention
        MB_CTODn: in std_logic;                         -- Massbus Controller TO Drive
        MB_RUN: in std_logic;                           -- Massbus Run signal
        MB_EXC: out std_logic;                          -- Massbus Exception signal
        MB_EBL: out std_logic;                          -- Massbus End of BLock signal
        MB_INIT: in std_logic;                          -- Massbus Initialize signal
        MB_DEM: in std_logic;                           -- Massbus Controller Demand signal
        MB_TRA: out std_logic;                          -- Massbus Transfer Acknowledge signal
        MB_OCC: out std_logic;                          -- Massbus Occupied (transfer in progress)
        MB_FAIL: in std_logic;                          -- Massbus Power Fail signal

        -- led bits
        LEDS: out std_logic_vector(7 downto 0)
        );
    end component;

signal    massbus_EXC: std_logic;                          -- Massbus Exception signal
signal    massbus_DEM: std_logic;                          -- Massbus Controller Demand signal
signal    massbus_RUN: std_logic;                           -- Massbus Run signal
--signal    massbus_CPA: std_logic;                        -- Massbus Control Parity

begin

    an_mde: MDE port map (
        RESET => RESET,
        LCLK => LCLK,

        -- bus interface signals --
        LW_R => LW_R,
        ADS => ADS,
        BLAST => BLAST,
        READY => READY,
        BTERM => BTERM,
        INT => INT,
        DREQ => DREQ,
        HOLD => HOLD,
        HOLDA => HOLDA,
        CCS => CCS,
        DISABLECONF => DISABLECONF,

        LAD => LAD,
        LBE => LBE,

        --      These signals will connect to the 5i22 IOBITS

        MB_D(1)          => IOBITS(0),
        MB_D(0)          => IOBITS(1),
        MB_D(3)          => IOBITS(2),
        MB_D(2)          => IOBITS(3),
        MB_D(5)          => IOBITS(4),
        MB_D(4)          => IOBITS(5),
        MB_D(7)          => IOBITS(32),
        MB_D(6)          => IOBITS(33),
        MB_D(9)          => IOBITS(34),
        MB_D(8)          => IOBITS(35),
        MB_D(11)         => IOBITS(36),
        MB_D(10)         => IOBITS(37),
        MB_D(13)         => IOBITS(48),
        MB_D(12)         => IOBITS(49),
        MB_D(15)         => IOBITS(50),
        MB_D(14)         => IOBITS(51),
        MB_D(17)         => IOBITS(52),
        MB_D(16)         => IOBITS(53),
        MB_C(1)          => IOBITS(6),
        MB_C(0)          => IOBITS(7),
        MB_C(3)          => IOBITS(8),
        MB_C(2)          => IOBITS(9),
        MB_C(5)          => IOBITS(10),
        MB_C(4)          => IOBITS(11),
        MB_C(7)          => IOBITS(38),
        MB_C(6)          => IOBITS(39),
        MB_C(9)          => IOBITS(40),
        MB_C(8)          => IOBITS(41),
        MB_C(11)         => IOBITS(42),
        MB_C(10)         => IOBITS(43),
        MB_C(13)         => IOBITS(55),
        MB_C(12)         => IOBITS(56),
        MB_C(15)         => IOBITS(57),
        MB_C(14)         => IOBITS(58),
        MB_SCLK          => IOBITS(12),
        MB_RS(0)         => IOBITS(46),
        MB_RS(1)         => IOBITS(47),
        MB_RS(2)         => IOBITS(13),
        MB_RS(3)         => IOBITS(14),
        MB_RS(4)         => IOBITS(17),
        MB_ATTN          => IOBITS(15),
        MB_TRA           => IOBITS(16),
        MB_DS(0)         => IOBITS(18),
        MB_DS(1)         => IOBITS(61),
        MB_DS(2)         => IOBITS(62),
        MB_OCC           => IOBITS(19),
        IEL_DRVH1        => IOBITS(24),
        RECV_DRV_CNTL    => IOBITS(25),
        IEL_DRVH2        => IOBITS(26),
        CNTRL_BUS_ENABLE => IOBITS(27),
        MB_WCLK          => IOBITS(28),
        MB_CTODn         => IOBITS(29),
        MB_RUN           => massbus_RUN,
        MB_INIT          => IOBITS(31),
        MB_EBL           => IOBITS(44),
        MB_EXC           => massbus_EXC,
        MB_DPA           => IOBITS(54),
        MB_CPA           => IOBITS(59),
        MB_DEM           => massbus_DEM,
        MB_FAIL          => IOBITS(63),

        LEDS => LEDS
        );

    IOBITS(45) <= not massbus_EXC;
    massbus_RUN <= not IOBITS(30);
    massbus_DEM <= not IOBITS(60);

    IOBITS(23 downto 20) <= (others => '0');
    IOBITS(95 downto 64) <= (others => '0');

end dataflow;
