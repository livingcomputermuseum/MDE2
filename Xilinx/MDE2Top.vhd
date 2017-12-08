-- -----------------------------------------------------------------------
-- Massbus Disk Emulator2 Top Level
-- Bruce Sherry
-- Copyright 2013-2017 Vulcan Inc
-- Developed by Living Computers: Museum+Labs, Seattle WA
-- Created 11/6/2013 12:28:29 PM
-- Version: 1.00
-- Date: 11/6/2013 12:28:39 PM

-- 0.00         First version to SVN. BS 10/10/2013 9:08:42 AM
-- 0.00 -> 0.01 Getting Drive select bits correct. BS 10/21/2013 10:36:06 AM
-- 0.01 -> 1.00 Stolen from UPETopMDI.vhd BS 11/6/2013 12:28:39 PM
-- -----------------------------------------------------------------------/

library IEEE;
use IEEE.std_logic_1164.all;  -- defines std_logic types
use IEEE.std_logic_ARITH.ALL;
use IEEE.std_logic_UNSIGNED.ALL;
--use work.IDROMConst.all;	
--use work.i22_1000card.all;		-- needs 5i22.ucf and SP3 1000K 320 pin
-- 96 I/O pinouts for 5I22:
--use work.PIN_SV16_96.all;

entity MDE2Top is  -- for 5I22 PCI9054 based card
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
	
    LAD: inout std_logic_vector (31 downto 0); 		-- data/address bus
	LBE: in std_logic_vector (3 downto 0); 			-- byte enables

	IOBITS: inout std_logic_vector (95 downto 0);	-- external I/O bits		

	-- led bits
	LEDS: out std_logic_vector(7 downto 0)
	);
end MDE2Top;

architecture dataflow of MDE2Top is

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
    	
        LAD: inout std_logic_vector (31 downto 0); 		-- data/address bus
    	LBE: in std_logic_vector (3 downto 0); 			-- byte enables
    
    --	These signals will connect to the 5i22 IOBITS
    
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
    
    --	These signals will connect to the 5i22 IOBITS
    
        IEL_DRVH1 => IOBITS(0),
        IEL_DRVH2 => IOBITS(2),
        RECV_DRV_CNTL => IOBITS(1),
        CNTRL_BUS_ENABLE => IOBITS(3),
        MB_D(0) => IOBITS(4),
        MB_D(1) => IOBITS(5),
        MB_D(2) => IOBITS(6),
        MB_D(3) => IOBITS(7),
        MB_D(4) => IOBITS(8),
        MB_D(5) => IOBITS(9),
        MB_D(6) => IOBITS(10),
        MB_D(7) => IOBITS(11),
        MB_D(8) => IOBITS(12),
        MB_D(9) => IOBITS(13),
        MB_D(10) => IOBITS(14),
        MB_D(11) => IOBITS(15),
        MB_D(12) => IOBITS(16),
        MB_D(13) => IOBITS(17),
        MB_D(14) => IOBITS(18),
        MB_D(15) => IOBITS(19),
        MB_D(16) => IOBITS(20),
        MB_D(17) => IOBITS(21),
        MB_DPA => IOBITS(22),
        MB_C(0) => IOBITS(23),
        MB_C(1) => IOBITS(58),
        MB_C(2) => IOBITS(24),
        MB_C(3) => IOBITS(25),
        MB_C(4) => IOBITS(26),
        MB_C(5) => IOBITS(27),
        MB_C(6) => IOBITS(28),
        MB_C(7) =>  IOBITS(29),
        MB_C(8) =>  IOBITS(30),
        MB_C(9) =>  IOBITS(31),
        MB_C(10) => IOBITS(32),
        MB_C(11) => IOBITS(33),
        MB_C(12) => IOBITS(34),
        MB_C(13) => IOBITS(35),
        MB_C(14) => IOBITS(36),
        MB_C(15) => IOBITS(37),
        MB_CPA => IOBITS(38),
        MB_SCLK => IOBITS(39),
        MB_WCLK => IOBITS(40),
        MB_RS(0) => IOBITS(41),
        MB_RS(1) => IOBITS(42),
        MB_RS(2) => IOBITS(43),
        MB_RS(3) => IOBITS(44),
        MB_RS(4) => IOBITS(45),
        MB_DS(0) => IOBITS(46),
        MB_DS(1) => IOBITS(47),
        MB_DS(2) => IOBITS(59),
        MB_ATTN => IOBITS(48),
        MB_CTODn => IOBITS(49),
        MB_RUN => IOBITS(50),
        MB_EXC => IOBITS(51),
        MB_EBL => IOBITS(52),
        MB_INIT => IOBITS(53),
        MB_TRA => IOBITS(55),
        MB_OCC => IOBITS(54),
        MB_DEM => IOBITS(56),
        MB_FAIL => IOBITS(57),

		LEDS => LEDS	
		);
	
	IOBITS(95 downto 60) <= (others => '0');
	
end dataflow;
