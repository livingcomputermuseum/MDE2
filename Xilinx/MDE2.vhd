-- -----------------------------------------------------------------------
-- Massbus Disk Emulator
-- Bruce Sherry
-- C. Vulcan, Inc. Living Computer Museum
-- Created from MDE_test.vhd 11/6/2013 6:43:51 AM
-- Version: 2.29
-- Date: 2/22/2016 2:51:07 PM
--
-- Memory Map
--     Address          Function    Description
-- 000000xxxxxxxxxx     rw          drive registers (128x16)
-- 0000010000000000     w           drives_online
-- 000001xxxxxxxxxx     r           drives_online
-- 0000100000000000     w           data clock divisor
-- 000010xxxxxxxxxx     r           data clock divisor
-- 0000110000000000     w           Transfer delay register
-- 000011xxxxxxxxxx     r           Transfer delay register
-- 0001000000000000     r           commmand fifo
-- 1xxxxxxxxxxxxxxx     rw          Data Transfer Fifos
--
-- 1.11 -> 2.00 SVN:02 Stolen from MDE_test.vhd. BS 11/6/2013 6:44:48 AM
-- 2.00 -> 2.01 SVN:03 Simulates. BS 11/13/2013 9:46:15 AM
-- 2.01 -> 2.02 SVN:04 Added read and write counts, version, fixed c bus, and cleanup. 
--                     Qualified commands with drives_online. BS 11/14/2013 1:08:21 PM
-- 2.02 -> 2.03 SVN:05 Seems to work. Fixed bus drive inversion, ATN, and several PCI
--                     signal problems. BS 11/15/2013 9:07:34 AM
-- 2.03 -> 2.04 SVN:06 fixed several problems with attention. BS 
-- 2.04 -> 2.05 SVN:07 Disabled parity checking on writes to the Attn_Sumary register. BS 11/20/2013 8:45:55 AM
-- 2.05 -> 2.08 SVN:08 Fixed polarity of ready, and got ready in line with data on disk writes. BS 11/22/2013 8:23:40 AM
-- 2.08 -> 2.09 SVN:   Moved counters around and fixed 3rd and 4th words of read headers. BS 11/27/2013 10:31:43 AM
-- 2.09 -> 2.10 SVN:09 Corrected erroneous errors at end of demand. BS 12/2/2013 8:51:42 AM
-- 2.10 -> 2.11 SVN:10 Registered LED outputs so they meet timing. BS 12/2/2013 1:13:08 PM
-- 2.11 -> 2.12 SVN:11 Changed default status to dual port. BS 12/5/2013 7:32:27 AM
-- 2.12 -> 2.13 SVN:12 Really changed it to dual port. BS 12/5/2013 9:22:22 AM
--                       Incremented sector etc. after end of transfer too. Inhibited sending nop commands too.
-- 2.13 -> 2.14 SVN:13 Added media_change_attn to unload. Tweaked MOL/VV from the PCI bus. BS 12/6/2013 10:23:26 AM
-- 2.14 -> 2.15 SVN 14 Make writing toj serial number register safe. BS 12/6/2013 2:52:10 PM
-- 2.15 -> 2.16 SVN:15 Stop trashing the serial number. BS 12/7/2013 8:57:45 PM
-- 2.16 -> 2.17 SVN:16 Moved PCI writes of Massbus Regs to help MOL changes. BS 12/8/2013 11:31:22 AM
-- 2.17 -> 2.18 Allow different drive types on one cable. BS 3/10/2014 2:11:12 PM
-- 2.18 -> 2.19 Changed demand delay to a counter, rcv/drv control to just CtoD, and removed changing drive type on re-init. BS 3/27/2014 8:42:02 AM
-- 2.19 -> 2.20 Added re_init and command_clear into data fifo reset. BS 3/28/2014 2:01:29 PM
-- 2.20 -> 2.21 SVN:19 Put drive configuration bits into Address Error logic and moved this logic to data commands. BS 3/31/2014 2:42:26 PM
-- 2.21 -> 2.22 Experimental avoid clearing sector address on reinit. BS 5/15/2014 2:40:30 PM
-- 2.22 -> 2.23 Added separate Recal Delay. BS 5/20/2014 12:39:08 PM
-- 2.23 -> 2.24 SVN:20 Allow writing to the drive type register. BS 5/20/2014 1:20:15 PM
-- 2.24 -> 2.25 Moved end of sector handling and wrttemp_valid out of enclosing if, because
--      -> 2.25 the RH could have selected another drive then. BS 1/14/2015 9:52:55 AM
-- 2.25 -> 2.26 Sped up Searches, and made attention bits separate signals. BS 7/9/2015 9:22:22 AM
-- 2.26 -> 2.27 Protected massbus register writes only with massbus_fail. BS 1/20/2016 2:12:28 PM
-- 2.27 -> 2.28 Added massbus_fail to bit 8 of drives_online register. BS 1/28/2016 8:13:52 AM
-- 2.28 -> 2.29 Moved clearing seek delay attention to valid commands. BS 2/22/2016 2:51:07 PM
--
-- -----------------------------------------------------------------------/


library IEEE;
use IEEE.std_logic_1164.all;  -- defines std_logic types
use IEEE.std_logic_ARITH.ALL;
use IEEE.std_logic_UNSIGNED.ALL;
use work.IDROMConst.all;	
use work.i22_1000card.all;		-- needs 5i22.ucf and SP3 1000K 320 pin
-- 96 I/O pinouts for 5I22:
use work.PIN_SV16_96.all;

entity MDE is  -- for 5I22 PCI9054 based card
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
--  WAITOUT: in std_logic;
--  LOCKO: in std_logic;
    DREQ: out std_logic;
    HOLD: in std_logic; 
    HOLDA: inout std_logic;
    CCS: out std_logic;
    DISABLECONF: out std_logic;
    
    LAD: inout std_logic_vector (31 downto 0); 		-- data/address bus
    LBE: in std_logic_vector (3 downto 0); 			-- byte enables

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
end MDE;

architecture behavioral of MDE is

constant MAJOR_REVISION: integer := 2;
constant MINOR_REVISION: integer := 29;
constant SECTOR_WORDS: integer := 255;
constant MAX_SECTOR: std_logic_vector := "00010011";
constant MAX_HEAD: std_logic_vector := "00010010";
constant MAX_CYLINDER: std_logic_vector := "000001100101110";
constant EBL_FALSE: std_logic := '1';
constant ADS_TRUE: std_logic := '0';
constant LW_R_WRITE: std_logic := '1';
constant LW_R_READ: std_logic := '0';
constant EBL_TRUE: std_logic := '0';
constant RUN_TRUE: std_logic := '0';
constant OCC_TRUE: std_logic := '1';
constant OCC_FALSE: std_logic := '0';
constant ATTN_TRUE: std_logic := '1';
constant ATTN_FALSE: std_logic := '0';
constant READY_TRUE: std_logic := '0';
constant READY_FALSE: std_logic := '1';
constant DBUSREAD_TRUE: std_logic := '0';
constant DBUSREAD_FALSE: std_logic := '1';
constant RCVDRIVE_TRUE: std_logic := '0';
constant RCVDRIVE_FALSE: std_logic := '1';

constant REG_COMMAND: std_logic_vector           := "00000"; -- 000
constant REG_STATUS: std_logic_vector            := "00001"; -- 001
constant REG_ERROR1: std_logic_vector            := "00010"; -- 002
constant REG_MAINT: std_logic_vector             := "00011"; -- 003
constant REG_ATTENTION: std_logic_vector         := "00100"; -- 004
constant REG_TRKSEC: std_logic_vector            := "00101"; -- 005
constant REG_DRVTYPE: std_logic_vector           := "00110"; -- 006
constant REG_LOOKAHD: std_logic_vector           := "00111"; -- 007
constant REG_SERNUM: std_logic_vector            := "01000"; -- 010
constant REG_OFFSET: std_logic_vector            := "01001"; -- 011
constant REG_DESCYL: std_logic_vector            := "01010"; -- 012
constant REG_CURCYL: std_logic_vector            := "01011"; -- 013
constant REG_ERROR2: std_logic_vector            := "01100"; -- 014
constant REG_ERROR3: std_logic_vector            := "01101"; -- 015
constant REG_ECC1: std_logic_vector              := "01110"; -- 016
constant REG_ECC2: std_logic_vector              := "01111"; -- 017

constant CMD_NOP: std_logic_vector               := "000001";  -- 0x01      001
constant CMD_UNLOAD: std_logic_vector            := "000011";  -- 0x03      003
constant CMD_SEEK: std_logic_vector              := "000101";  -- 0x05      005
constant CMD_RECALIBRATE: std_logic_vector       := "000111";  -- 0x07      007
constant CMD_DRIVE_CLEAR: std_logic_vector       := "001001";  -- 0x09      011
constant CMD_RELEASE: std_logic_vector           := "001011";  -- 0x0b      013
constant CMD_OFFSET: std_logic_vector            := "001101";  -- 0x0d      015
constant CMD_RETURN_TO_CENTER: std_logic_vector  := "001111";  -- 0x0f      017
constant CMD_READ_IN_PRESET: std_logic_vector    := "010001";  -- 0x11      021
constant CMD_PACK_ACK: std_logic_vector          := "010011";  -- 0x13      023
constant CMD_ERASE: std_logic_vector             := "010101";  -- 0x15      025
constant CMD_WR_FILEM: std_logic_vector          := "010111";  -- 0x17      027
constant CMD_SEARCH: std_logic_vector            := "011001";  -- 0x19      031
constant CMD_BACKSPACE: std_logic_vector         := "011011";  -- 0x1b      033
constant CMD_WRITE_CHK_DATA: std_logic_vector    := "101001";  -- 0x29      051
constant CMD_WRITE_CHK_HDR_DATA: std_logic_vector := "101011"; -- 0x2b      053
constant CMD_WRITE_DATA: std_logic_vector        := "110001";  -- 0x31      061
constant CMD_WRITE_HDR_DATA: std_logic_vector    := "110011";  -- 0x33      063
constant CMD_READ_DATA: std_logic_vector         := "111001";  -- 0x39      071
constant CMD_READ_HDR_DATA: std_logic_vector     := "111011";  -- 0x3b      073
constant WRITE_DATA_CMDS: std_logic_vector       := "110";     --           06x 

constant ALL16ZEROS: std_logic_vector            := "0000000000000000"; 
constant DEF_COMMAND: std_logic_vector           := "0000100000000000"; -- 0x0800  
constant DEF_STATUS: std_logic_vector            := "0001001111000000"; -- 0x13c0 
constant DEF_DRVTYPE: std_logic_vector           := "0010100000010010"; -- 0x2812
constant RP07DRVTYPE: std_logic_vector           := "0010100000010010"; -- 0x2822
constant DEF_SERIALNM: std_logic_vector          := "0001001000110100"; -- 0x1234 
                                                
constant PRE_EBL_DELAY: std_logic_vector         := "00111011111"; -- ~10uS
constant EBL_DELAY: std_logic_vector             := "00001000010"; -- ~2.5uS
constant START_DELAY: std_logic_vector           := "00111011111"; -- ~10uS
-- constant START_DELAY: std_logic_vector           := "00011101111"; -- ~5uS
                                                
constant MBC_GO:  integer                        := 0;  -- 0000100 // Command GO
constant MBC_DRY: integer                        := 7;  -- 0000200 // drive ready
constant MBC_DVA: integer                        := 11; -- 0004000 // Drive Available
                                                
constant MBS_VV:  integer                        := 6;  -- 0000100 // volume valid
constant MBS_DRY: integer                        := 7;  -- 0000200 // drive ready
constant MBS_DPR: integer                        := 8;  -- 0000400 // drive present
constant MBS_SPR: integer                        := 9;  -- 0000400 // Programmable (not port A and not port B)
constant MBS_LBT: integer                        := 10; -- 0002000 // last block transferred
constant MBS_WRL: integer                        := 11; -- 0004000 // write locked
constant MBS_MOL: integer                        := 12; -- 0010000 // medium online
constant MBS_PIP: integer                        := 13; -- 0020000 // position in progress
constant MBS_ERR: integer                        := 14; -- 0040000 // OR of all error bits
constant MBS_ATA: integer                        := 15; -- 0100000 // attention active
                                                
constant MBE1_ILF: integer                       := 0;  -- 0000001 // Illegal function
constant MBE1_ILR: integer                       := 1;  -- 0000002 // Illegal register
constant MBE1_RMR: integer                       := 2;  -- 0000004 // Register Modification Refused
constant MBE1_PAR: integer                       := 3;  -- 0000010 // Control/Data Bus Parity Error
constant MBE1_FER: integer                       := 4;  -- 0000020 // format Error
constant MBE1_AOE: integer                       := 9;  -- 0001000 // Address Overflow Error
constant MBE1_IAE: integer                       := 10; -- 0002000 // Invalid Address Error
constant MBE1_WLE: integer                       := 11; -- 0004000 // Write Lock Error
constant MBE1_DTE: integer                       := 12; -- 0010000 // Drive timing Error 
constant MBE1_UNS: integer                       := 14; -- 0040000 // Operation Incomplete 
constant MBE1_OPI: integer                       := 13; -- 0020000 // Operation Incomplete 
constant MBE1_DCK: integer                       := 15; -- 0100000 // Data Check Error 

-- constant SEEK_DELAY_DEF: std_logic_vector(19 downto 0) := "00001011101110000000"; -- 48000 1ms
constant SEEK_DELAY_DEF:  std_logic_vector(19 downto 0) := "00000010111011100000"; -- 12000 250us
constant SEARCH_DELAY_DEF: std_logic_vector(19 downto 0) := "00000001011101110000"; -- 6000 125us
constant RECAL_DELAY_DEF: std_logic_vector(19 downto 0) := "00001011101110000000"; -- 48000 1ms

-- States for SCLK data read machine
type sclkstates is (WAITING, HDR1H, HDR1L, HDR2H, HDR2L, HDR3H, HDR3L, HDR4H, HDR4L, 
                    DELAY1, DELAY2, SCLK1, SCLK2, NXTWAIT, EBWAIT, EBL1, EBL2);
             
type reg_array is array (0 to 7) of std_logic_vector(15 downto 0);
type breg_array is array (0 to 7) of std_logic_vector(14 downto 0);
type smreg_array is array (0 to 7) of std_logic_vector(7 downto 0);
type counter_array is array (0 to 7) of std_logic_vector(19 downto 0);

signal    PCI_RESET: std_logic;

-- bus interface signals --
signal    PCI_LW_R: std_logic; 
signal    PCI_ADS: std_logic; 
signal    ads_delayed: std_logic_vector(0 to 3);
signal    PCI_BLAST: std_logic; 
signal    PCI_READY: std_logic;
signal    PCI_BTERM: std_logic;
signal    PCI_INT: std_logic := '1';
--  WAITOUT: std_logic;
--  LOCKO: std_logic;
signal    PCI_DREQ: std_logic;
signal    PCI_HOLD: std_logic; 
signal    PCI_CCS: std_logic;
signal    PCI_DISABLECONF: std_logic;

signal    PCI_LAD: std_logic_vector (31 downto 0); 		-- data/address bus
signal    PCI_LAD_OUT: std_logic_vector (31 downto 0); 		-- data/address bus
signal    pci_lad_en: std_logic;                        -- data/Address bus output enable
signal    PCI_LBE: std_logic_vector (3 downto 0); 			-- byte enables

--  These signals will connect to the 5i22 IOBITS

signal    massbus_IEL_DRVH: std_logic;                       -- Data Bus Drive Enable 1
signal    massbus_RECV_DRV_CNTL: std_logic;                   -- Read control bus
signal    massbus_CNTRL_BUS_ENABLE: std_logic;                -- Control Bus Drive Enable
signal    massbus_D: std_logic_vector(17 downto 0);      -- Massbus Data Bus
signal    massbus_D_OUT: std_logic_vector(17 downto 0);      -- Massbus Data Bus
signal    massbus_DPA: std_logic;                        -- Massbus Data Parity
signal    massbus_DPA_OUT: std_logic;                        -- Massbus Data Parity
signal    massbus_C: std_logic_vector(15 downto 0);      -- Massbus Control Bus
signal    massbus_C_OUT: std_logic_vector(15 downto 0);      -- Massbus Control Bus
signal    massbus_CPA: std_logic;                        -- Massbus Control Parity
signal    massbus_CPA_OUT: std_logic;                        -- Massbus Control Parity
signal    massbus_SCLK: std_logic;                         -- Massbus Data Sync Clock
signal    massbus_WCLK: std_logic;                          -- Massbus Data Write Clock
signal    massbus_RS: std_logic_vector(4 downto 0);         -- Massbus Register Select
signal    massbus_DS: std_logic_vector(2 downto 0);         -- Massbus Drive Select
signal    massbus_ATTN: std_logic;                         -- Massbus Attention
signal    massbus_CTODn: std_logic;                         -- Massbus Controller TO Drive
signal    massbus_RUN: std_logic;                           -- Massbus Run signal
signal    massbus_EXC: std_logic;                          -- Massbus Exception signal
signal    massbus_EBL: std_logic;                          -- Massbus End of BLock signal
signal    massbus_INIT: std_logic;                          -- Massbus Initialize signal
signal    massbus_DEM: std_logic;                           -- Massbus Controller Demand signal
signal    massbus_TRA: std_logic;                          -- Massbus Transfer Acknowledge signal
signal    massbus_OCC: std_logic;                          -- Massbus Occupied (transfer in progress)
signal    massbus_FAIL: std_logic;                          -- Massbus Power Fail signal


signal command_reg: reg_array   := (DEF_COMMAND,  -- 0
                                    DEF_COMMAND,
                                    DEF_COMMAND,
                                    DEF_COMMAND,
                                    DEF_COMMAND,
                                    DEF_COMMAND,
                                    DEF_COMMAND,
                                    DEF_COMMAND);
signal status_reg: reg_array    := (DEF_STATUS,   -- 1
                                    DEF_STATUS,
                                    DEF_STATUS,
                                    DEF_STATUS,
                                    DEF_STATUS,
                                    DEF_STATUS,
                                    DEF_STATUS,
                                    DEF_STATUS);
signal attn_drive0: std_logic;
signal attn_drive1: std_logic;
signal attn_drive2: std_logic;
signal attn_drive3: std_logic;
signal attn_drive4: std_logic;
signal attn_drive5: std_logic;
signal attn_drive6: std_logic;
signal attn_drive7: std_logic;
signal error1_reg: reg_array    := (ALL16ZEROS,   -- 2
                                    ALL16ZEROS,
                                    ALL16ZEROS,
                                    ALL16ZEROS,
                                    ALL16ZEROS,
                                    ALL16ZEROS,
                                    ALL16ZEROS,
                                    ALL16ZEROS);
signal maint_reg: std_logic_vector(15 downto 0)                 :=  ALL16ZEROS;   -- 3
signal attsum_reg: std_logic_vector(15 downto 0)                :=  ALL16ZEROS;   -- 4
signal trksec_reg: reg_array    := (ALL16ZEROS,   -- 5
                                    ALL16ZEROS,
                                    ALL16ZEROS,
                                    ALL16ZEROS,
                                    ALL16ZEROS,
                                    ALL16ZEROS,
                                    ALL16ZEROS,
                                    ALL16ZEROS);
signal drvtype_reg: reg_array   := (DEF_DRVTYPE,  -- 6
                                    DEF_DRVTYPE,
                                    DEF_DRVTYPE,
                                    DEF_DRVTYPE,
                                    DEF_DRVTYPE,
                                    DEF_DRVTYPE,
                                    DEF_DRVTYPE,
                                    DEF_DRVTYPE);
signal lookahd_reg: std_logic_vector(15 downto 0)               :=  ALL16ZEROS;   -- 7
signal sernum_reg: reg_array    := (DEF_SERIALNM, -- 10 
                                    DEF_SERIALNM,
                                    DEF_SERIALNM,
                                    DEF_SERIALNM,
                                    DEF_SERIALNM,
                                    DEF_SERIALNM,
                                    DEF_SERIALNM,
                                    DEF_SERIALNM);
signal offset_reg: std_logic_vector(15 downto 0)                :=  ALL16ZEROS;   -- 11
signal descyl_reg: reg_array    := (ALL16ZEROS,   -- 12
                                    ALL16ZEROS,
                                    ALL16ZEROS,
                                    ALL16ZEROS,
                                    ALL16ZEROS,
                                    ALL16ZEROS,
                                    ALL16ZEROS,
                                    ALL16ZEROS);
signal curcyl_reg: reg_array    := (ALL16ZEROS,   -- 13
                                   ALL16ZEROS,
                                   ALL16ZEROS,
                                   ALL16ZEROS,
                                   ALL16ZEROS,
                                   ALL16ZEROS,
                                   ALL16ZEROS,
                                   ALL16ZEROS);
signal error2_reg: std_logic_vector(15 downto 0)                :=  ALL16ZEROS;   -- 14
signal error3_reg: std_logic_vector(15 downto 0)                :=  ALL16ZEROS;   -- 15
signal ecc1_reg: std_logic_vector(15 downto 0)                  :=  ALL16ZEROS;   -- 16
signal ecc2_reg: std_logic_vector(15 downto 0)                  :=  ALL16ZEROS;   -- 17
signal set_attn_flop: std_logic_vector(7 downto 0)              := "00000000";
signal attn_flop: std_logic_vector(7 downto 0)                  := "00000000";
signal sectors_per_track: smreg_array := (MAX_SECTOR,
                                          MAX_SECTOR,
                                          MAX_SECTOR,
                                          MAX_SECTOR,
                                          MAX_SECTOR,
                                          MAX_SECTOR,
                                          MAX_SECTOR,
                                          MAX_SECTOR);
signal heads_per_cyl: smreg_array     := (MAX_HEAD,
                                          MAX_HEAD,
                                          MAX_HEAD,
                                          MAX_HEAD,
                                          MAX_HEAD,
                                          MAX_HEAD,
                                          MAX_HEAD,
                                          MAX_HEAD);
signal number_of_cyls: breg_array     := (MAX_CYLINDER,
                                          MAX_CYLINDER,
                                          MAX_CYLINDER,
                                          MAX_CYLINDER,
                                          MAX_CYLINDER,
                                          MAX_CYLINDER,
                                          MAX_CYLINDER,
                                          MAX_CYLINDER);
signal delay_line: std_logic_vector(7 downto 0)   := "00000000";     
signal demand: std_logic;
signal re_init: std_logic;
signal write_temp: std_logic_vector(15 downto 0);
signal write_reg: std_logic_vector(4 downto 0);
signal write_drive: std_logic_vector(2 downto 0);
signal wrtmp_valid: std_logic                      := '0';
signal set_wrtmp: std_logic                        := '0'; 
signal pci_cycle_in_process: std_logic             := '0';
signal pci_bus_address: std_logic_vector(15 downto 0);
signal drives_online: std_logic_vector(7 downto 0) := "00000001";
signal delay_max_reg: std_logic_vector(7 downto 0) := "00000111";
-- signal sclk_max_count: std_logic_vector(10 downto 0):= "00000001111"; -- 24 = 666nS per
-- signal sclk_max_count: std_logic_vector(10 downto 0):= "00000010111"; -- 24 = 1uS per
-- signal sclk_max_count: std_logic_vector(10 downto 0):= "00000011111"; -- 32 = 1.31uS per
-- signal sclk_max_count: std_logic_vector(10 downto 0):= "00000101111"; -- 48 = 2uS per
   signal sclk_max_count: std_logic_vector(10 downto 0):= "00001000010"; -- 67 = rp06 - 18 bit
-- signal sclk_max_count: std_logic_vector(10 downto 0):= "00001000111"; -- 72 = 3uS per
-- signal sclk_max_count: std_logic_vector(10 downto 0):= "00001011111"; -- 96 = 4uS per
-- signal sclk_max_count: std_logic_vector(10 downto 0):= "00010000001"; -- 129
signal seek_delay_reg: counter_array := ("00000000000000000000",
                                         "00000000000000000000",
                                         "00000000000000000000",
                                         "00000000000000000000",
                                         "00000000000000000000",
                                         "00000000000000000000",
                                         "00000000000000000000",
                                         "00000000000000000000");
signal seek_delay_attn: std_logic_vector(7 downto 0);
signal send_command: std_logic;
signal command_fifo_rd_data: std_logic_vector(35 downto 0);
signal command_fifo_wr_data: std_logic_vector(35 downto 0);
signal command_ready_n: std_logic;
signal cmdrdy: std_logic;
signal datardy: std_logic;
signal data_run: std_logic;
signal command_fifo_read: std_logic;
signal frompc_fifo_write: std_logic;
signal frompc_fifo_read: std_logic;
signal frompc_fifo_rd_data: std_logic_vector(17 downto 0);
signal frompc_fifo_wr_data: std_logic_vector(17 downto 0);
signal frompc_ready_n: std_logic;
signal topc_fifo_write: std_logic;
signal topc_fifo_read: std_logic;
signal topc_fifo_rd_data: std_logic_vector(17 downto 0);
signal topc_fifo_wr_data: std_logic_vector(17 downto 0);
signal topc_ready_n: std_logic;
Signal datafifo_reset: std_logic;
signal command_clear: std_logic;
signal occupied: std_logic;
signal sklock: std_logic;
signal blockend: std_logic;
signal dbus_read: std_logic := '0';
signal transferend: std_logic;
signal sclock_state: sclkstates := WAITING;
signal catch_wr_data: std_logic;
signal word_count: std_logic_vector(8 downto 0) := "000000000";
signal rerun: std_logic;
signal active_drive: std_logic_vector(2 downto 0);
signal wclk_delayed: std_logic;
signal set_wrdata_error: std_logic;
signal datapar_error_count: std_logic_vector(19 downto 0) := "00000000000000000000";
signal ctlpar_error_count: std_logic_vector(19 downto 0) := "00000000000000000000"; 
signal block_read_count: counter_array := ("00000000000000000000",
                                           "00000000000000000000",
                                           "00000000000000000000",
                                           "00000000000000000000",
                                           "00000000000000000000",
                                           "00000000000000000000",
                                           "00000000000000000000",
                                           "00000000000000000000");
signal block_write_count: counter_array := ("00000000000000000000",
                                            "00000000000000000000",
                                            "00000000000000000000",
                                            "00000000000000000000",
                                            "00000000000000000000",
                                            "00000000000000000000",
                                            "00000000000000000000",
                                            "00000000000000000000");
signal counter_temp: std_logic_vector(19 downto 0);
signal counter_temp_valid: std_logic;
signal counter_temp_reg: std_logic_vector(15 downto 0);

COMPONENT fifo_generator_v9_3
    PORT (
        clk : IN STD_LOGIC;
        rst : IN STD_LOGIC;
        din : IN STD_LOGIC_VECTOR(17 DOWNTO 0);
        wr_en : IN STD_LOGIC;
        rd_en : IN STD_LOGIC;
        dout : OUT STD_LOGIC_VECTOR(17 DOWNTO 0);
        full : OUT STD_LOGIC;
        almost_full : OUT STD_LOGIC;
        empty : OUT STD_LOGIC
    );
END COMPONENT;

Component fifo_generator_v9_3_36
    PORT (
        clk : IN STD_LOGIC;
        rst : IN STD_LOGIC;
        din : IN STD_LOGIC_VECTOR(35 DOWNTO 0);
        wr_en : IN STD_LOGIC;
        rd_en : IN STD_LOGIC;
        dout : OUT STD_LOGIC_VECTOR(35 DOWNTO 0);
        full : OUT STD_LOGIC;
        empty : OUT STD_LOGIC
    );
END COMPONENT;

begin
    -- This process is to force input/output registers into the IOB's.
    iob_registers: process (LCLK)
    begin
        if LCLK'event and LCLK = '1' then
            PCI_RESET <= RESET;             -- in std_logic;
            
            -- bus interface signals --
            PCI_LW_R <= LW_R;               -- in std_logic; 
            PCI_ADS <= ADS;                 -- in std_logic; 
            PCI_BLAST <= BLAST;             -- in std_logic; 
            if PCI_READY = READY_TRUE then  -- out std_logic;
                READY <= READY_TRUE;
            else
                READY <= READY_FALSE;
            end if;
            BTERM <= '1';             -- out std_logic;
            -- LAD bus enable has to run from the pins!
            if PCI_ADS = ADS_TRUE and LW_R = LW_R_READ then
                pci_lad_en <= '1';
            elsif PCI_READY = READY_TRUE then
                pci_lad_en <= '0';
            end if;
            
            PCI_LAD <= LAD; 		        -- data/address bus
            if pci_lad_en = '1' then
                LAD <= PCI_LAD_OUT;
            else
                LAD <= "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ";
            end if;
            
            PCI_LBE <= LBE;                 -- in std_logic_vector (3 downto 0); 			-- byte enables
            
            --  These signals will connect to the 5i22 IOBITS
            
            IEL_DRVH1 <= MASSBUS_IEL_DRVH;                   -- Data Bus Drive Enable 1
            IEL_DRVH2 <= MASSBUS_IEL_DRVH;                   -- Data Bus Drive Enable 2
            RECV_DRV_CNTL <= MASSBUS_RECV_DRV_CNTL;          -- Read control bus
            CNTRL_BUS_ENABLE <= MASSBUS_CNTRL_BUS_ENABLE;    -- Control Bus Drive Enable
            
            massbus_D <= MB_D;
            massbus_DPA <= MB_DPA;
            if dbus_read = DBUSREAD_TRUE then
                MB_D <= "ZZZZZZZZZZZZZZZZZZ";
                MB_DPA <= 'Z';
            else
                MB_D <= massbus_D_OUT;
                MB_DPA <= massbus_DPA_OUT;
            end if;
            
            massbus_C <= MB_C;
            massbus_CPA <= MB_CPA;
            if (MASSBUS_CNTRL_BUS_ENABLE = '1'  and drives_online(conv_integer(massbus_DS)) = '1') or
                massbus_RS = REG_ATTENTION then
                MB_C <= massbus_C_OUT;
                MB_CPA <= massbus_CPA_OUT;
            else
                MB_C <= "ZZZZZZZZZZZZZZZZ";
                MB_CPA <= 'Z';
            end if;
            
            MB_SCLK <= massbus_SCLK;                         -- Massbus Data Sync Clock
            massbus_WCLK <= MB_WCLK;                         -- Massbus Data Write Clock
            massbus_RS <= MB_RS;                             -- Massbus Register Select
            massbus_DS <= MB_DS;                             -- Massbus Drive Select
            MB_ATTN <= massbus_ATTN;                         -- Massbus Attention
            massbus_CTODn <= MB_CTODn;                       -- Massbus Controller TO Drive
            massbus_RUN <= MB_RUN;                           -- Massbus Run signal
            MB_EXC <= massbus_EXC;                           -- Massbus Exception signal
            MB_EBL <= massbus_EBL;                           -- Massbus End of BLock signal
            massbus_INIT <= MB_INIT;                         -- Massbus Initialize signal
            massbus_DEM <= MB_DEM;                           -- Massbus Controller Demand signal
            MB_TRA <= massbus_TRA;                           -- Massbus Transfer Acknowledge signal
            MB_OCC <= massbus_OCC;                           -- Massbus Occupied (transfer in progress)
            massbus_FAIL <= MB_FAIL;                         -- Massbus Power Fail signal
        end if;
    end process;

    INT <= PCI_INT;                 -- out std_logic;
    --  WAITOUT: in std_logic;
    --  LOCKO: in std_logic;
    DREQ <= '0';               -- out std_logic;
    PCI_HOLD <= HOLD;               -- in std_logic; 
    HOLDA <= PCI_HOLD;              -- inout std_logic;
--            HOLDA <= PCI_HOLD;              -- inout std_logic;
    CCS <= '1';                 -- out std_logic;
    DISABLECONF <= 'Z'; -- out std_logic;
            

-- Process to generate READY for the PCI bus. This will be implemented as a shift Register
-- tapped at the appropriate place to generate ready.
    ready_generate: process (LCLK)
    begin
        if LCLK'event and LCLK = '1' then
            ads_delayed <= not PCI_ADS & ads_delayed(0 to 2);
            -- always delay one cycle for pci accesses
--		    PCI_READY <= PCI_ADS;
            if ads_delayed(0) = '1' then
		        PCI_READY <= READY_TRUE;
		    else
		        PCI_READY <= READY_FALSE;
		    end if;
        end if;
    end process;

-- Process to validate the MB_DEM signal. It must be valid for the length of
--  the delay line for the demand signal to become valid. Roughly 6 clocks, or 120ns.
-- There is a wart that if the Demand is exactly as long as our delay, we will issue
--  a ~20ns Transfer one clock after Demand goes away, and change the register then
--  if it was a Write.
    demand_validate: process (LCLK)
    begin
        if LCLK'event and LCLK = '1' then
            if massbus_DEM = '0' then
                delay_line <= "00000000";          
                demand <= '0';                     
            elsif delay_line <= delay_max_reg then 
                delay_line <= delay_line + 1;
                demand <= '0';
            else
                demand <= '1';
            end if;
        end if;
    end process;
    
-- Default these signals for now...
    PCI_BTERM <= '1';
    PCI_DREQ <= '0';
	PCI_DISABLECONF <= 'Z'; -- No DMA so don't disable Conf
	PCI_CCS <= '1';
    
-- cerate an imaginary SCLK for now...
    sclock : process (LCLK)
        variable sclock_div: std_logic_vector(10 downto 0);
        variable dbus_out: std_logic_vector(17 downto 0) := "ZZZZZZZZZZZZZZZZZZ";
        variable i: integer;
    begin
        if LCLK'event and LCLK = '1' and massbus_FAIL = '0' then
            if re_init = '1' or occupied = OCC_FALSE then
                sclock_div := "00000000000";
                word_count <= "000000000";
                sklock <= '0';
                sclock_state <= WAITING;
                blockend <= EBL_FALSE;
                dbus_read <= DBUSREAD_TRUE;
                transferend <= '0';
                rerun <= '0';
                dbus_out := "ZZZZZZZZZZZZZZZZZZ";
                frompc_fifo_read <= '0';
                catch_wr_data <= '0';
            elsif data_run = '1' then
                -- We are running!
                if command_reg(conv_integer(active_drive))(5 downto 0) = CMD_WRITE_DATA then
                    case sclock_state is
                        when WAITING => -- waiting
                            blockend <= EBL_FALSE;
                            dbus_read <= DBUSREAD_TRUE;
                            rerun <= '0';
                            -- wait till run is true
                            if massbus_RUN = RUN_TRUE then
                                sclock_state <= DELAY1;
                            else
                                sclock_state <= WAITING;
                            end if;
                            sclock_div := sclock_div + 1;
                            transferend <= '0';
                            sklock <= '0';
                            catch_wr_data <= '0';
                        when DELAY1 =>
                            dbus_read <= DBUSREAD_TRUE;
                            if sclock_div < START_DELAY then
                                sklock <= '0';
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sklock <= '0';
                                sclock_state <= DELAY2;
                                catch_wr_data <= '1';
                            end if;
                        when DELAY2 =>
                            dbus_read <= DBUSREAD_TRUE;
                            if sclock_div < START_DELAY then
                                sklock <= '0';
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sklock <= '1';
                                sclock_state <= SCLK1;
                            end if;
                        when SCLK1 => -- SCLK high
                            dbus_read <= DBUSREAD_TRUE;
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                                sklock <= '1';
                            else
                                sclock_div := "00000000000";
                                sklock <= '0';
                                sclock_state <= SCLK2;
                            end if;
                        when SCLK2 => -- SCLK low
                            dbus_read <= DBUSREAD_TRUE;
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                                sklock <= '0';
                            else
                                sclock_div := "00000000000";
                                if word_count < SECTOR_WORDS then
                                    sklock <= '1';
                                    sclock_state <= SCLK1;
                                    word_count <= word_count + 1;
                                else
                                    sklock <= '0';
                                    sclock_state <= EBWAIT;
                                end if;
                            end if;
                        when EBWAIT =>
                            sklock <= '0';
                            if sclock_div < PRE_EBL_DELAY then
                                sclock_div := sclock_div + 1;
                            else
                                if topc_ready_n = '1' then
                                    sclock_div := "00000000000";
                                    sclock_state <= EBL1;
                                else
                                    sclock_state <= EBWAIT;
                                end if;
                            end if;
                        when EBL1 => -- first half of massbus_EBL
                            sklock <= '0';
                            blockend <= EBL_TRUE;
                            dbus_read <= DBUSREAD_TRUE;
                            frompc_fifo_read <= '0';
                            if sclock_div < EBL_DELAY then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sclock_state <= EBL2;
                                catch_wr_data <= '0';
                            end if;
                        when EBL2 => -- second half of massbus_EBL
                            sklock <= '0';
                            dbus_read <= DBUSREAD_TRUE;
                            frompc_fifo_read <= '0';
                            if sclock_div < EBL_DELAY then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                word_count <= "000000000";
                                sclock_state <= WAITING;
                                if massbus_RUN = RUN_TRUE then
                                    rerun <= '1';
                                else
                                    rerun <= '0';
                                    transferend <= '1';
                                end if;
                            end if;
                        when others =>
                            sklock <= '0';
                            sclock_div := "00000000000";
                            dbus_read <= DBUSREAD_TRUE;
                            sclock_state <= WAITING;
                    end case;
                    dbus_out := "ZZZZZZZZZZZZZZZZZZ";
                    frompc_fifo_read <= '0';
                elsif command_reg(conv_integer(active_drive))(5 downto 0) = CMD_WRITE_HDR_DATA then
                    case sclock_state is
                        when WAITING => -- waiting
                            blockend <= EBL_FALSE;
                            dbus_read <= DBUSREAD_TRUE;
                            rerun <= '0';
                            -- wait till run is true
                            if massbus_RUN = RUN_TRUE then
                                sclock_state <= DELAY1;
                            else
                                sclock_state <= WAITING;
                            end if;
                            sclock_div := sclock_div + 1;
                            transferend <= '0';
                            sklock <= '0';
                            catch_wr_data <= '0';
                        when DELAY1 =>
                            dbus_read <= DBUSREAD_TRUE;
                            if sclock_div < START_DELAY then
                                sklock <= '0';
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sklock <= '0';
                                sclock_state <= DELAY2;
                            end if;
                        when DELAY2 =>
                            dbus_read <= DBUSREAD_TRUE;
                            if sclock_div < START_DELAY then
                                sklock <= '0';
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sklock <= '1';
                                sclock_state <= HDR1H;
                            end if;
                        when HDR1H =>
                            dbus_read <= DBUSREAD_TRUE;
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                                sklock <= '1';
                            else
                                sclock_div := "00000000000";
                                sklock <= '0';
                                sclock_state <= HDR1L;
                            end if;
                        when HDR1L =>
                            dbus_read <= DBUSREAD_TRUE;
                            if sclock_div < sclk_max_count then
                                sklock <= '0';
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sklock <= '1';
                                sclock_state <= HDR2H;
                            end if;
                        when HDR2H =>
                            dbus_read <= DBUSREAD_TRUE;
                            if sclock_div < sclk_max_count then
                                sklock <= '1';
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sklock <= '0';
                                sclock_state <= HDR2L;
                            end if;
                        when HDR2L =>
                            dbus_read <= DBUSREAD_TRUE;
                            if sclock_div < sclk_max_count then
                                sklock <= '0';
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sklock <= '1';
                                sclock_state <= HDR3H;
                            end if;
                        when HDR3H =>
                            dbus_read <= DBUSREAD_TRUE;
                            if sclock_div < sclk_max_count then
                                sklock <= '1';
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sklock <= '0';
                                sclock_state <= HDR3L;
                            end if;
                        when HDR3L =>
                            dbus_read <= DBUSREAD_TRUE;
                            if sclock_div < sclk_max_count then
                                sklock <= '0';
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sklock <= '1';
                                sclock_state <= HDR4H;
                            end if;
                        when HDR4H =>
                            dbus_read <= DBUSREAD_TRUE;
                            if sclock_div < sclk_max_count then
                                sklock <= '1';
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sklock <= '0';
                                sclock_state <= HDR4L;
                                catch_wr_data <= '1';
                            end if;
                        when HDR4L =>
                            dbus_read <= DBUSREAD_TRUE;
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sklock <= '1';
                                sclock_state <= SCLK1;
                                word_count <= "000000000";
                            end if;
                        when SCLK1 => -- SCLK high
                            dbus_read <= DBUSREAD_TRUE;
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                                sklock <= '1';
                            else
                                sclock_div := "00000000000";
                                sklock <= '0';
                                sclock_state <= SCLK2;
                            end if;
                        when SCLK2 => -- SCLK low
                            dbus_read <= DBUSREAD_TRUE;
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                                sklock <= '0';
                            else
                                sclock_div := "00000000000";
                                if word_count < SECTOR_WORDS then
                                    sklock <= '1';
                                    sclock_state <= SCLK1;
                                    word_count <= word_count + 1;
                                else
                                    sclock_state <= EBWAIT;
                                end if;
                            end if;
                        when EBWAIT =>
                            sklock <= '0';
                            if sclock_div < PRE_EBL_DELAY then
                                sclock_div := sclock_div + 1;
                            else
                                if topc_ready_n = '1' then
                                    sclock_div := "00000000000";
                                    sclock_state <= EBL1;
                                else
                                    sclock_state <= EBWAIT;
                                end if;
                            end if;
                        when EBL1 => -- first half of massbus_EBL
                            sklock <= '0';
                            blockend <= EBL_TRUE;
                            dbus_read <= DBUSREAD_TRUE;
                            frompc_fifo_read <= '0';
                            if sclock_div < EBL_DELAY then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sclock_state <= EBL2;
                                catch_wr_data <= '0';
                            end if;
                        when EBL2 => -- second half of massbus_EBL
                            sklock <= '0';
                            dbus_read <= DBUSREAD_TRUE;
                            frompc_fifo_read <= '0';
                            if sclock_div < EBL_DELAY then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                word_count <= "000000000";
                                sclock_state <= WAITING;
                                if massbus_RUN = RUN_TRUE then
                                    rerun <= '1';
                                else
                                    rerun <= '0';
                                    transferend <= '1';
                                end if;
                            end if;
                        when others =>
                            sklock <= '0';
                            sclock_div := "00000000000";
                            dbus_read <= DBUSREAD_TRUE;
                            sclock_state <= WAITING;
                    end case;
                    dbus_out := "ZZZZZZZZZZZZZZZZZZ";
                    frompc_fifo_read <= '0';
                elsif command_reg(conv_integer(active_drive))(5 downto 0) = CMD_WRITE_CHK_DATA  or
                      command_reg(conv_integer(active_drive))(5 downto 0) = CMD_READ_DATA then
                    -- simple read or write check command...
                    case sclock_state is
                        when WAITING => -- waiting
                            sklock <= '0';
                            blockend <= EBL_FALSE;
                            dbus_read <= DBUSREAD_TRUE;
                            transferend <= '0';
                            rerun <= '0';
                            if (frompc_ready_n = '0') and (massbus_RUN = RUN_TRUE) then
                                frompc_fifo_read <= '1';
                                sclock_state <= SCLK1;
                            else
                                sclock_state <= WAITING;
                            end if;
                            dbus_out := "ZZZZZZZZZZZZZZZZZZ";
                        when SCLK1 => -- SCLK high
                            sklock <= '1';
                            dbus_read <= DBUSREAD_FALSE;
                            frompc_fifo_read <= '0';
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sclock_state <= SCLK2;
                            end if;
                            dbus_out := frompc_fifo_rd_data;
                        when SCLK2 => -- SCLK low
                            sklock <= '0';
                            dbus_read <= DBUSREAD_FALSE;
                            frompc_fifo_read <= '0';
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                if word_count < SECTOR_WORDS then
                                    if frompc_ready_n = '1' then
                                        sclock_state <= WAITING;
                                    else
                                        sclock_state <= SCLK1;
                                        frompc_fifo_read <= '1';
                                    end if;
                                    word_count <= word_count + 1;
                                else
                                    sclock_state <= EBWAIT;
                                    dbus_out := "ZZZZZZZZZZZZZZZZZZ";
                                end if;
                            end if;
                        when EBWAIT =>
                            sklock <= '0';
                            if sclock_div < PRE_EBL_DELAY then
                                sclock_div := sclock_div + 1;
                            else
                                if topc_ready_n = '1' then
                                    sclock_div := "00000000000";
                                    sclock_state <= EBL1;
                                else
                                    sclock_state <= EBWAIT;
                                end if;
                            end if;
                        when EBL1 => -- first half of massbus_EBL
                            blockend <= EBL_TRUE;
                            dbus_read <= DBUSREAD_FALSE;
                            frompc_fifo_read <= '0';
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sclock_state <= EBL2;
                            end if;
                            dbus_out := "ZZZZZZZZZZZZZZZZZZ";
                        when EBL2 => -- second half of massbus_EBL
                            frompc_fifo_read <= '0';
                            dbus_read <= DBUSREAD_FALSE;
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sclock_state <= WAITING;
                                word_count <= "000000000";
                                if massbus_RUN = RUN_TRUE then
                                    rerun <= '1';
                                else
                                    rerun <= '0';
                                    transferend <= '1';
                                end if;
                            end if;
                            dbus_out := "ZZZZZZZZZZZZZZZZZZ";
                        when others =>
                            blockend <= EBL_FALSE;
                            frompc_fifo_read <= '0';
                            sclock_div := "00000000000";
                            word_count <= "000000000";
                            sclock_state <= WAITING;
                            dbus_read <= DBUSREAD_TRUE;
                            dbus_out := "ZZZZZZZZZZZZZZZZZZ";
                            rerun <= '0';
                    end case;
                elsif command_reg(conv_integer(active_drive))(5 downto 0) = CMD_READ_HDR_DATA then
                    -- simple read or write check command...
                    case sclock_state is
                        when WAITING => -- waiting
                            sklock <= '0';
                            blockend <= EBL_FALSE;
                            dbus_read <= DBUSREAD_TRUE;
                            transferend <= '0';
                            rerun <= '0';
                            if (frompc_ready_n = '0') and (massbus_RUN = RUN_TRUE) then
                                sclock_state <= HDR1H;
                                dbus_out := "00" & descyl_reg(conv_integer(active_drive));
                            else
                                sclock_state <= WAITING;
                            end if;
                            dbus_out := "ZZZZZZZZZZZZZZZZZZ";
                        when HDR1H => -- SCLK high
                            sklock <= '1';
                            dbus_read <= DBUSREAD_FALSE;
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sclock_state <= HDR1L;
                            end if;
                            dbus_out := "00" & descyl_reg(conv_integer(active_drive));
                        when HDR1L => -- SCLK low
                            sklock <= '0';
                            dbus_read <= DBUSREAD_FALSE;
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sclock_state <= HDR2H;
                                dbus_out := "00" & trksec_reg(conv_integer(active_drive));
                            end if;
                        when HDR2H => -- SCLK high
                            sklock <= '1';
                            dbus_read <= DBUSREAD_FALSE;
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sclock_state <= HDR2L;
                            end if;
                            dbus_out := "00" & trksec_reg(conv_integer(active_drive));
                        when HDR2L => -- SCLK low
                            sklock <= '0';
                            dbus_read <= DBUSREAD_FALSE;
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sclock_state <= HDR3H;
                                dbus_out := "000000000000000000";
                            end if;
                        when HDR3H => -- SCLK high
                            sklock <= '1';
                            dbus_read <= DBUSREAD_FALSE;
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sclock_state <= HDR3L;
                                dbus_out := "000000000000000000";
                            end if;
                        when HDR3L => -- SCLK low
                            sklock <= '0';
                            dbus_read <= DBUSREAD_FALSE;
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sclock_state <= HDR4H;
                                dbus_out := "000000000000000000";
                            end if;
                        when HDR4H => -- SCLK high
                            sklock <= '1';
                            dbus_read <= DBUSREAD_FALSE;
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sclock_state <= HDR4L;
                                dbus_out := "000000000000000000";
                            end if;
                        when HDR4L => -- SCLK low
                            sklock <= '0';
                            dbus_read <= DBUSREAD_FALSE;
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sclock_state <= SCLK1;
                                frompc_fifo_read <= '1';
                            end if;
                            dbus_out := frompc_fifo_rd_data;
                        when SCLK1 => -- SCLK high
                            sklock <= '1';
                            dbus_read <= DBUSREAD_FALSE;
                            frompc_fifo_read <= '0';
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sclock_state <= SCLK2;
                            end if;
                            dbus_out := frompc_fifo_rd_data;
                        when SCLK2 => -- SCLK low
                            sklock <= '0';
                            dbus_read <= DBUSREAD_FALSE;
                            frompc_fifo_read <= '0';
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                if word_count < SECTOR_WORDS then
                                    if frompc_ready_n = '1' then
                                        sclock_state <= NXTWAIT;
                                    else
                                        sclock_state <= SCLK1;
                                        frompc_fifo_read <= '1';
                                    end if;
                                    word_count <= word_count + 1;
                                else
                                    sclock_state <= EBWAIT;
                                    dbus_out := "ZZZZZZZZZZZZZZZZZZ";
                                end if;
                            end if;
                        when NXTWAIT =>
                            if frompc_ready_n = '0' then
                                sclock_state <= SCLK1;
                                frompc_fifo_read <= '1';
                            end if;
                        when EBWAIT =>
                            sklock <= '0';
                            if sclock_div < PRE_EBL_DELAY then
                                sclock_div := sclock_div + 1;
                            else
                                if topc_ready_n = '1' then
                                    sclock_div := "00000000000";
                                    sclock_state <= EBL1;
                                else
                                    sclock_state <= EBWAIT;
                                end if;
                            end if;
                        when EBL1 => -- first half of massbus_EBL
                            blockend <= EBL_TRUE;
                            dbus_read <= DBUSREAD_FALSE;
                            frompc_fifo_read <= '0';
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sclock_state <= EBL2;
                            end if;
                            dbus_out := "ZZZZZZZZZZZZZZZZZZ";
                        when EBL2 => -- second half of massbus_EBL
                            frompc_fifo_read <= '0';
                            dbus_read <= DBUSREAD_FALSE;
                            if sclock_div < sclk_max_count then
                                sclock_div := sclock_div + 1;
                            else
                                sclock_div := "00000000000";
                                sclock_state <= WAITING;
                                word_count <= "000000000";
                                if massbus_RUN = RUN_TRUE then
                                    rerun <= '1';
                                else
                                    rerun <= '0';
                                    transferend <= '1';
                                end if;
                            end if;
                            dbus_out := "ZZZZZZZZZZZZZZZZZZ";
                        when others =>
                            blockend <= EBL_FALSE;
                            frompc_fifo_read <= '0';
                            sclock_div := "00000000000";
                            word_count <= "000000000";
                            sclock_state <= WAITING;
                            dbus_read <= DBUSREAD_TRUE;
                            rerun <= '0';
                    end case;
                end if;
                
            end if;

            -- make it real
            massbus_SCLK <= sklock; 
            massbus_EBL <= blockend;  
            MASSBUS_IEL_DRVH <= dbus_read;    
            MASSBUS_IEL_DRVH <= dbus_read;    
            -- handle the actual dbus data:
            massbus_D_OUT <= dbus_out;
            massbus_DPA_OUT <= dbus_out(17) xor dbus_out(16) xor dbus_out(15) xor
                               dbus_out(14) xor dbus_out(13) xor dbus_out(12) xor
                               dbus_out(11) xor dbus_out(10) xor dbus_out(9) xor
                               dbus_out(8)  xor dbus_out(7)  xor dbus_out(6) xor
                               dbus_out(5)  xor dbus_out(4)  xor dbus_out(3) xor
                               dbus_out(2)  xor dbus_out(1)  xor not dbus_out(0);
            
        end if; 
    end process;
    
-- Do the overall reset thing...
    re_init <= not PCI_RESET or massbus_INIT or 
               (not command_reg(0)(5) and not command_reg(0)(4) and command_reg(0)(3) and
                not command_reg(0)(2) and not command_reg(0)(1) and command_reg(0)(MBC_GO)) or
               (not command_reg(1)(5) and not command_reg(1)(4) and command_reg(1)(3) and
                not command_reg(1)(2) and not command_reg(1)(1) and command_reg(1)(MBC_GO)) or
               (not command_reg(2)(5) and not command_reg(2)(4) and command_reg(2)(3) and
                not command_reg(2)(2) and not command_reg(2)(1) and command_reg(2)(MBC_GO)) or
               (not command_reg(3)(5) and not command_reg(3)(4) and command_reg(3)(3) and
                not command_reg(3)(2) and not command_reg(3)(1) and command_reg(3)(MBC_GO)) or
               (not command_reg(4)(5) and not command_reg(4)(4) and command_reg(4)(3) and
                not command_reg(4)(2) and not command_reg(4)(1) and command_reg(4)(MBC_GO)) or
               (not command_reg(5)(5) and not command_reg(5)(4) and command_reg(5)(3) and
                not command_reg(5)(2) and not command_reg(5)(1) and command_reg(5)(MBC_GO)) or
               (not command_reg(6)(5) and not command_reg(6)(4) and command_reg(6)(3) and
                not command_reg(6)(2) and not command_reg(6)(1) and command_reg(6)(MBC_GO)) or
               (not command_reg(7)(5) and not command_reg(7)(4) and command_reg(7)(3) and
                not command_reg(7)(2) and not command_reg(7)(1) and command_reg(7)(MBC_GO));
    
-- Do a simple emulation of the drive registers ingnoring the drive select lines,
-- only writing some registers.    
	Massbus_regs: process (LCLK, massbus_RUN, topc_ready_n)
	    variable bus_out: std_logic_vector(15 downto 0);
	    constant MAX_SECTS: std_logic_vector(4 downto 0) := "10011";
	    constant MAX_HEADS: std_logic_vector(4 downto 0) := "10010";
	    variable transfer: std_logic;
	    variable cmd_fifo_write: std_logic;
	    variable cp_in: std_logic;
	    variable i: integer;
        variable attention: std_logic_vector(7 downto 0) := "00000000";
        variable sector_delay_counter: std_logic_vector(15 downto 0) := "0000000000000000";
        constant SECTOR_DELAY_MAX: std_logic_vector(15 downto 0)     := "1001110001000000"; -- 40000
        variable clear_attention: std_logic;
        variable media_change_attn: std_logic_vector(7 downto 0); -- set when the software mounts a pack
        variable exception_hold: std_logic := '0';
        variable status_error_bit: std_logic;
	begin
        if LCLK'event and LCLK = '1' then
            
            -- Calculate Control bus parity...    
            cp_in := (massbus_C(15) xor massbus_C(14) xor massbus_C(13) xor massbus_C(12) xor massbus_C(11) xor massbus_C(10) xor
                      massbus_C(9)  xor massbus_C(8)  xor massbus_C(7)  xor massbus_C(6)  xor massbus_C(5)  xor massbus_C(4)  xor
                      massbus_C(3)  xor massbus_C(2)  xor massbus_C(1)  xor massbus_C(0) xor massbus_CPA);   
              
            -- seek delay counter
            for i in 7 downto 0 loop
                if (seek_delay_reg(i) = 1) then
                    seek_delay_attn(i) <= '1';
                    command_reg(i)(MBC_GO) <= '0';
                    command_reg(i)(MBC_DRY) <= '1';
                    status_reg(i)(MBS_DRY) <= '1';
                    status_reg(i)(MBS_PIP) <= '0';
--                else
--                    seek_delay_attn(i) <= '0';
                end if;
    
                if (seek_delay_reg(i) > 0) then
                    seek_delay_reg(i) <= seek_delay_reg(i) - 1;
                end if;
            end loop;
            
            -- clear media attention
            for i in 7 downto 0 loop
                media_change_attn(i) := '0';
            end loop;
                       
            -- sector counter
            if (sector_delay_counter = "0000000000000000") then
                sector_delay_counter := SECTOR_DELAY_MAX;
                -- (@@) make 8 lookahd_registers?
                if lookahd_reg(7 downto 0) < sectors_per_track(0) then
                    lookahd_reg(7 downto 0) <= lookahd_reg(7 downto 0) + 1;
                else
                    lookahd_reg(7 downto 0) <= "00000000";
                end if;
            else
                sector_delay_counter := sector_delay_counter - 1;
            end if;
              
            -- don't bother the command fifo unless we are supposed to...
            cmd_fifo_write := '0';
            
            -- start with no RESET
            command_clear <= '0';
            
            if re_init = '0' and (drives_online(conv_integer(massbus_DS)) = '1' or massbus_RS = REG_ATTENTION)  then
                if massbus_CTODn = '0' and massbus_FAIL = '0' then
                    -- this is a write: don't drive the control bus
                    MASSBUS_CNTRL_BUS_ENABLE <= '0';
                    
                    -- Read what he is saying
                    MASSBUS_RECV_DRV_CNTL <= '0';
                     
                    if demand = '1' and transfer = '0' then
                        -- do the write case
                        -- parity is disabled
                        if cp_in = '1' or massbus_RS = REG_ATTENTION then
                            clear_attention := '0';
                            case massbus_RS is
                                when REG_COMMAND => -- command_reg
                                    command_reg(conv_integer(massbus_DS))(5 downto 0) <= massbus_C(5 downto 0);
                                    
                                    -- if it is a data movement command, send it up to the 
                                    -- pc.
                                    if massbus_C(5 downto 0) = CMD_WRITE_CHK_DATA or
                                       massbus_C(5 downto 0) = CMD_WRITE_DATA or
                                       massbus_C(5 downto 0) = CMD_READ_DATA or
                                       massbus_C(5 downto 0) = CMD_READ_HDR_DATA or
                                       massbus_C(5 downto 0) = CMD_WRITE_HDR_DATA then
                                       if drives_online(conv_integer(massbus_DS)) = '1' then
                                            if trksec_reg(conv_integer(massbus_DS))(7 DOWNTO 0) <= sectors_per_track(conv_integer(massbus_DS)) and
                                               trksec_reg(conv_integer(massbus_DS))(15 downto 8) <= heads_per_cyl(conv_integer(massbus_DS)) and
                                               descyl_reg(conv_integer(massbus_DS)) <= number_of_cyls(conv_integer(massbus_DS)) then
                                                error1_reg(conv_integer(massbus_DS))(MBE1_IAE) <= '0'; 
                                                cmd_fifo_write := '1';
                                                command_fifo_wr_data <= "00000000000000000" & massbus_DS &
                                                                        command_reg(conv_integer(massbus_DS))(15 downto 8) & "00" & massbus_C(5 downto 0);
                                                active_drive <= massbus_DS;
                                                -- @@ check for valid command
                                                status_reg(conv_integer(massbus_DS))(MBS_DRY) <= '0';
                                                command_reg(conv_integer(massbus_DS))(MBC_DRY) <= '0';
                                                occupied <= OCC_TRUE;
                                                
                                                -- increment the counters...
                                                if massbus_C(5 downto 3) = WRITE_DATA_CMDS then
                                                    block_write_count(conv_integer(massbus_DS)) <= block_write_count(conv_integer(massbus_DS)) + 1;
                                                else
                                                    block_read_count(conv_integer(massbus_DS)) <= block_read_count(conv_integer(massbus_DS)) + 1;
                                                end if;
                                                data_run <= '1';
                                                -- Valid commands clear Attention
                                                seek_delay_attn(conv_integer(massbus_DS)) <= '0';
                                                clear_attention := '1';
                                            else
                                                error1_reg(conv_integer(massbus_DS))(MBE1_IAE) <= '1';
                                            end if;
                                       end if;
                                        
                                    elsif massbus_C(5 downto 0) = CMD_UNLOAD then
                                        cmd_fifo_write := '1';
                                        command_fifo_wr_data <= "00000000000000000" & massbus_DS &
                                                                command_reg(conv_integer(massbus_DS))(15 downto 8) & "00" & massbus_C(5 downto 0);
                                        active_drive <= massbus_DS;
                                        status_reg(conv_integer(massbus_DS))(MBS_VV) <= '0';
                                        status_reg(conv_integer(massbus_DS))(MBS_MOL) <= '0';
                                        media_change_attn(conv_integer(massbus_DS)) := '1';
                                        
                                    elsif massbus_C(5 downto 0) = CMD_ERASE or
                                          massbus_C(5 downto 0) = CMD_WR_FILEM or
                                          massbus_C(5 downto 0) = CMD_BACKSPACE then
                                        cmd_fifo_write := '1';
                                        command_fifo_wr_data <= "00000000000000000" & massbus_DS &
                                                                command_reg(conv_integer(massbus_DS))(15 downto 8) & "00" & massbus_C(5 downto 0);
                                        active_drive <= massbus_DS;
                                        -- @@ check for valid command
                                        status_reg(conv_integer(massbus_DS))(MBS_DRY) <= '0';
                                        command_reg(conv_integer(massbus_DS))(MBC_DRY) <= '0';
                                        -- Valid commands clear Attention
                                        seek_delay_attn(conv_integer(massbus_DS)) <= '0';
                                        clear_attention := '1';
                                        
                                   elsif massbus_C(5 downto 0) = CMD_PACK_ACK then
                                        status_reg(conv_integer(massbus_DS))(MBS_VV) <= '1';
                                        command_reg(conv_integer(massbus_DS))(MBC_GO) <= '0';
                                        command_reg(conv_integer(massbus_DS))(MBC_DRY) <= '1';
                                        -- Valid commands clear Attention
                                        seek_delay_attn(conv_integer(massbus_DS)) <= '0';
                                        clear_attention := '1';
                                        
                                    elsif massbus_C(5 downto 0) = CMD_SEARCH then
                                        lookahd_reg <= trksec_reg(conv_integer(massbus_DS));
                                        sector_delay_counter := SECTOR_DELAY_MAX;
                                        seek_delay_reg(conv_integer(massbus_DS)) <= SEARCH_DELAY_DEF;
                                        status_reg(conv_integer(massbus_DS))(MBS_DRY) <= '0';
                                        -- Valid commands clear Attention
                                         seek_delay_attn(conv_integer(massbus_DS)) <= '0';
                                       clear_attention := '1';
                                        
                                    elsif massbus_C(5 downto 0) = CMD_RECALIBRATE then
                                        descyl_reg(conv_integer(massbus_DS))(9 downto 0) <= "0000000000";
                                        curcyl_reg(conv_integer(massbus_DS))(9 downto 0) <= "0000000000";
                                        offset_reg(7 downto 0) <= "00000000";
                                        seek_delay_reg(conv_integer(massbus_DS)) <= RECAL_DELAY_DEF;
                                        status_reg(conv_integer(massbus_DS))(MBS_DRY) <= '0';
                                        status_reg(conv_integer(massbus_DS))(MBS_PIP) <= '1';
                                        -- Valid commands clear Attention
                                        seek_delay_attn(conv_integer(massbus_DS)) <= '0';
                                        clear_attention := '1';
                                        
                                    elsif massbus_C(5 downto 0) = CMD_SEEK or
                                        massbus_C(5 downto 0) = CMD_OFFSET then
                                        seek_delay_reg(conv_integer(massbus_DS)) <= SEEK_DELAY_DEF;
                                        status_reg(conv_integer(massbus_DS))(MBS_DRY) <= '0';
                                        status_reg(conv_integer(massbus_DS))(MBS_PIP) <= '1';
                                        -- Valid commands clear Attention
                                        seek_delay_attn(conv_integer(massbus_DS)) <= '0';
                                        clear_attention := '1';
                                        
                                   elsif massbus_C(5 downto 0) = CMD_READ_IN_PRESET then
                                        descyl_reg(conv_integer(massbus_DS))(9 downto 0) <= "0000000000";
                                        offset_reg(7 downto 0) <= "00000000";
                                        command_reg(conv_integer(massbus_DS))(MBC_GO) <= '0';
                                        command_reg(conv_integer(massbus_DS))(MBC_DRY) <= '1';
                                        -- Valid commands clear Attention
                                        seek_delay_attn(conv_integer(massbus_DS)) <= '0';
                                        clear_attention := '1';
                                        
                                   elsif massbus_C(5 downto 0) = CMD_RETURN_TO_CENTER then
                                        offset_reg(7 downto 0) <= "00000000";
                                        seek_delay_reg(conv_integer(massbus_DS)) <= SEEK_DELAY_DEF;
                                        status_reg(conv_integer(massbus_DS))(MBS_DRY) <= '0';
                                        status_reg(conv_integer(massbus_DS))(MBS_PIP) <= '1';
                                        -- Valid commands clear Attention
                                        seek_delay_attn(conv_integer(massbus_DS)) <= '0';
                                        clear_attention := '1';
                                        
                                    elsif massbus_C(5 downto 0) = CMD_NOP or
                                          massbus_C(5 downto 0) = CMD_RELEASE then
                                        if status_reg(conv_integer(massbus_DS))(MBS_VV) = '1' and
                                           status_reg(conv_integer(massbus_DS))(MBS_MOL) = '1' then
                                            -- Valid commands clear Attention
                                            seek_delay_attn(conv_integer(massbus_DS)) <= '0';
                                            clear_attention := '1';
                                        else
                                            error1_reg(conv_integer(massbus_DS))(MBE1_UNS) <= '0';
                                        end if;    
                                        command_reg(conv_integer(massbus_DS))(MBC_GO) <= '0';
                                        command_reg(conv_integer(massbus_DS))(MBC_DRY) <= '1';
                                           
                                    elsif massbus_C(5 downto 0) = CMD_DRIVE_CLEAR then
                                        if status_reg(conv_integer(massbus_DS))(MBS_VV) = '1' and
                                           status_reg(conv_integer(massbus_DS))(MBS_MOL) = '1' then
                                            trksec_reg(conv_integer(massbus_DS)) <= ALL16ZEROS;
                                            descyl_reg(conv_integer(massbus_DS))( 9 downto 0) <= "0000000000";
                                            offset_reg(7 downto 0) <= "00000000";
                                            error1_reg(conv_integer(massbus_DS)) <= "0000000000000000";
                                            error2_reg <= "0000000000000000";
                                            error3_reg <= "0000000000000000";
                                            ecc1_reg <= "0000000000000000";
                                            ecc2_reg <= "0000000000000000";
                                            -- Valid commands clear Attention
                                            seek_delay_attn(conv_integer(massbus_DS)) <= '0';
                                            clear_attention := '1';
                                        else
                                            error1_reg(conv_integer(massbus_DS))(MBE1_UNS) <= '0';
                                        end if;    
                                        command_reg(conv_integer(massbus_DS))(MBC_GO) <= '0';
                                        command_reg(conv_integer(massbus_DS))(MBC_DRY) <= '1';
                                        command_clear <= '1';
                                    elsif massbus_C(0) = '1' then
                                     -- other commands should set illegal function
                                        error1_reg(conv_integer(massbus_DS))( MBE1_ILF) <= '1';
                                    end if;
                                    
                                    -- Actually clear the attention bits
                                    if clear_attention = '1' then
                                        case massbus_DS is
                                        when "000" =>
                                            attn_drive0 <= '0';
                                        when "001" =>
                                            attn_drive1 <= '0';
                                        when "010" =>
                                            attn_drive2 <= '0';
                                        when "011" =>
                                            attn_drive3 <= '0';
                                        when "100" =>
                                            attn_drive4 <= '0';
                                        when "101" =>
                                            attn_drive5 <= '0';
                                        when "110" =>
                                            attn_drive6 <= '0';
                                        when "111" =>
                                            attn_drive7 <= '0';
                                        when others =>
                                        end case;
                                    end if;
                                when REG_ATTENTION =>
                                     if massbus_C(0) = '1' and attn_drive0 = '1' then
                                         attn_drive0 <= '0';
                                     end if;
                                     if massbus_C(1) = '1' and attn_drive1 = '1' then
                                         attn_drive1 <= '0';
                                     end if;
                                     if massbus_C(2) = '1' and attn_drive2 = '1' then
                                         attn_drive2 <= '0';
                                     end if;
                                     if massbus_C(3) = '1' and attn_drive3 = '1' then
                                         attn_drive3 <= '0';
                                     end if;
                                     if massbus_C(4) = '1' and attn_drive4 = '1' then
                                         attn_drive4 <= '0';
                                     end if;
                                     if massbus_C(5) = '1' and attn_drive5 = '1' then
                                         attn_drive5 <= '0';
                                     end if;
                                     if massbus_C(6) = '1' and attn_drive6 = '1' then
                                         attn_drive6 <= '0';
                                     end if;
                                     if massbus_C(7) = '1' and attn_drive7 = '1' then
                                         attn_drive7 <= '0';
                                     end if;
                                when REG_TRKSEC => -- trksec_reg
                                    trksec_reg(conv_integer(massbus_DS)) <= massbus_C;
                                    sector_delay_counter := SECTOR_DELAY_MAX;
                                when REG_DESCYL => -- descyl_reg
                                    descyl_reg(conv_integer(massbus_DS))(9 downto 0) <= massbus_c(9 downto 0);
                                    curcyl_reg(conv_integer(massbus_DS))(9 downto 0) <= massbus_c(9 downto 0);
                                when REG_SERNUM => -- Serial number For Tops-10
                                    -- Don't do anything.
                                when REG_DRVTYPE => -- Drive Type For Tops-20s & WAITS
                                    -- Don't do anything.
                                when REG_OFFSET => -- offset_reg
                                    offset_reg <= massbus_c;
                                when others =>
                                    error1_reg(conv_integer(massbus_DS))(MBE1_ILR) <= '1';
                                    if massbus_C(0) = '1' then
                                        cmd_fifo_write := '1';
                                        command_fifo_wr_data <= "00000000000000000" & massbus_DS &
                                                                command_reg(conv_integer(massbus_DS))(15 downto 8) & "00" & massbus_C(5 downto 0);
                                    end if;
                            end case;
                        else -- bad control bus parity
                            if massbus_RS /=   REG_ATTENTION then
                                error1_reg(conv_integer(massbus_DS))(MBE1_PAR) <= '1';
                                ctlpar_error_count <= ctlpar_error_count + 1;
                            end if;
                        end if;
                    end if;   -- demand rising edge
                else -- this is a read

                    status_error_bit := error1_reg(conv_integer(massbus_DS))(15) or error1_reg(conv_integer(massbus_DS))(14) or error1_reg(conv_integer(massbus_DS))(13) or error1_reg(conv_integer(massbus_DS))(12) or
                         error1_reg(conv_integer(massbus_DS))(11) or error1_reg(conv_integer(massbus_DS))(10) or error1_reg(conv_integer(massbus_DS))(9)  or error1_reg(conv_integer(massbus_DS))(8)  or
                         error1_reg(conv_integer(massbus_DS))(7)  or error1_reg(conv_integer(massbus_DS))(6)  or error1_reg(conv_integer(massbus_DS))(5)  or error1_reg(conv_integer(massbus_DS))(4)  or
                         error1_reg(conv_integer(massbus_DS))(3)  or error1_reg(conv_integer(massbus_DS))(2)  or error1_reg(conv_integer(massbus_DS))(1)  or error1_reg(conv_integer(massbus_DS))(0)  or
                         error2_reg(15) or error2_reg(14) or error2_reg(13) or error2_reg(12) or
                         error2_reg(11) or error2_reg(10) or error2_reg(9)  or error2_reg(8)  or
                         error2_reg(7)  or error2_reg(6)  or error2_reg(5)  or error2_reg(4)  or
                         error2_reg(3)  or error2_reg(2)  or error2_reg(1)  or error2_reg(0)  or
                         error3_reg(15) or error3_reg(14) or error3_reg(13) or error3_reg(12) or
                         error3_reg(11) or error3_reg(10) or error3_reg(9)  or error3_reg(8)  or
                         error3_reg(7)  or error3_reg(6)  or error3_reg(5)  or error3_reg(4)  or
                         error3_reg(3)  or error3_reg(2)  or error3_reg(1)  or error3_reg(0);
                         
                    -- Handle Massbus reads. If we just wrote one from the PCI,
                    -- the Massbus will get stale data.
                    MASSBUS_RECV_DRV_CNTL <= '1';
                    if (massbus_DEM = '1' or demand = '1') then
                        -- do the read case
                        MASSBUS_CNTRL_BUS_ENABLE <= '1';
                        case massbus_RS is
                            when REG_COMMAND =>
                                bus_out := command_reg(conv_integer(massbus_DS))(15 downto 8) & not command_reg(conv_integer(massbus_DS))(MBC_GO) & command_reg(conv_integer(massbus_DS))(6 downto 0);
                            when REG_STATUS =>
                                bus_out := status_reg(conv_integer(massbus_DS))(15) & status_error_bit & status_reg(conv_integer(massbus_DS))(13 downto 0);
                            when REG_ERROR1 =>
                                -- disabling ilegal register error.
                                bus_out := error1_reg(conv_integer(massbus_DS))(15 downto 2) & '0' & error1_reg(conv_integer(massbus_DS))(0);
                            when REG_MAINT =>
                                bus_out := maint_reg;
                            when REG_ATTENTION =>
                                bus_out := "00000000" & attn_drive7 & attn_drive6 & attn_drive5 &
                                    attn_drive4 & attn_drive3 & attn_drive2 & attn_drive1 & attn_drive0;
                            when REG_TRKSEC =>
                                bus_out := trksec_reg(conv_integer(massbus_DS));
                            when REG_DRVTYPE =>
                                bus_out := drvtype_reg(conv_integer(massbus_DS));
                            when REG_LOOKAHD =>
                                bus_out := lookahd_reg;
                            when REG_SERNUM =>
                                bus_out := sernum_reg(conv_integer(massbus_DS));
                            when REG_OFFSET =>
                                bus_out := offset_reg;
                            when REG_DESCYL =>
                                bus_out := descyl_reg(conv_integer(massbus_DS));
                            when REG_CURCYL =>
                                bus_out := curcyl_reg(conv_integer(massbus_DS));
                            when REG_ERROR2 =>
                                bus_out := error2_reg;
                            when REG_ERROR3 =>
                                bus_out := error3_reg;
                            when REG_ECC1 =>
                                bus_out := ecc1_reg;
                            when REG_ECC2 =>
                                bus_out := ecc2_reg;
                            when others =>
                                if massbus_DEM = '1' then
                                    error1_reg(conv_integer(massbus_DS))(MBE1_ILR) <= '1';
                                    bus_out := "ZZZZZZZZZZZZZZZZ";
                                    cmd_fifo_write := '1';
                                    command_fifo_wr_data <= "00000000000000000" & massbus_DS &
                                                             command_reg(conv_integer(massbus_DS))(15 downto 8) & "00" & massbus_C(5 downto 0);
                                end if;
                        end case;
                        massbus_C_OUT <= bus_out;
                        massbus_CPA_OUT <= not (bus_out(15) xor bus_out(14) xor bus_out(13) xor bus_out(12) xor
                                   bus_out(11) xor bus_out(10) xor bus_out(9)  xor bus_out(8) xor 
                                   bus_out(7)  xor bus_out(6)  xor bus_out(5)  xor bus_out(4) xor
                                   bus_out(3)  xor bus_out(2)  xor bus_out(1)  xor bus_out(0));
                    else
                        massbus_C_OUT <= "ZZZZZZZZZZZZZZZZ";
                        massbus_CPA_OUT <= 'Z';
                        MASSBUS_CNTRL_BUS_ENABLE <= '0';
                    end if;
                end if;
                
                -- handle massbus_RUN staying up during data commands
                if rerun = '1' then
                    if trksec_reg(conv_integer(active_drive))(7 downto 0) < sectors_per_track(conv_integer(active_drive)) then
                        trksec_reg(conv_integer(active_drive))(7 downto 0) <= trksec_reg(conv_integer(active_drive))( 7 downto 0) + 1;
                    else
                        trksec_reg(conv_integer(active_drive))(7 downto 0) <= "00000000";
                        if trksec_reg(conv_integer(active_drive))(15 downto 8) < heads_per_cyl(conv_integer(active_drive)) then
                            trksec_reg(conv_integer(active_drive))(15 downto 8) <= trksec_reg(conv_integer(active_drive))(15 downto 8) + 1;
                        else
                            trksec_reg(conv_integer(active_drive))(15 downto 8) <= "00000000";
                            descyl_reg(conv_integer(active_drive))  <= descyl_reg(conv_integer(active_drive)) + 1;
                            -- @@ fails if he tries to roll over drives
                        end if;
                    end if;
                    
                    -- tell the PC host that he asked for the next sector
                    cmd_fifo_write := '1';
                    command_fifo_wr_data <= "00000000000000000" & active_drive &
                                            command_reg(conv_integer(active_drive));
                end if;
                
                -- handle write data parity errors
                if set_wrdata_error = '1' then
                    exception_hold := '1';
                end if;
        
            elsif re_init = '1' then
                for i in 7 downto 0 loop
                    command_reg(i) <= DEF_COMMAND;
                    status_reg(i)  <= DEF_STATUS;
                    error1_reg(i)  <= ALL16ZEROS;
--                    trksec_reg(i)  <= ALL16ZEROS;
--                    descyl_reg(i)  <= ALL16ZEROS;
                    curcyl_reg(i)  <= ALL16ZEROS;
                end loop;
                maint_reg   <= ALL16ZEROS;
                attsum_reg  <= ALL16ZEROS;
                lookahd_reg <= ALL16ZEROS;
                offset_reg  <= ALL16ZEROS;
                error2_reg  <= ALL16ZEROS;
                error3_reg  <= ALL16ZEROS;
                ecc1_reg    <= ALL16ZEROS;
                ecc2_reg    <= ALL16ZEROS;
                occupied    <= OCC_FALSE;
                exception_hold := '0';
                data_run <= '0';
            end if;
                
            -- end of sector handling...
            if transferend = '1' then
                command_reg(conv_integer(active_drive))(MBC_GO) <= '0';
                command_reg(conv_integer(active_drive))(MBC_DRY) <= '1';
                status_reg(conv_integer(active_drive))(MBS_DRY) <= '1';
                occupied <= OCC_FALSE;
                data_run <= '0';
                if trksec_reg(conv_integer(active_drive))(7 downto 0) < sectors_per_track(conv_integer(active_drive)) then
                    trksec_reg(conv_integer(active_drive))(7 downto 0) <= trksec_reg(conv_integer(active_drive))( 7 downto 0) + 1;
                else
                    trksec_reg(conv_integer(active_drive))(7 downto 0) <= "00000000";
                    if trksec_reg(conv_integer(active_drive))(15 downto 8) < heads_per_cyl(conv_integer(active_drive)) then
                        trksec_reg(conv_integer(active_drive))(15 downto 8) <= trksec_reg(conv_integer(active_drive))(15 downto 8) + 1;
                    else
                        trksec_reg(conv_integer(active_drive))(15 downto 8) <= "00000000";
                        descyl_reg(conv_integer(active_drive))  <= descyl_reg(conv_integer(active_drive)) + 1;
                        -- @@ fails if he tries to roll over drives
                    end if;
                end if;
                if exception_hold = '1' then
                        error1_reg(conv_integer(active_drive))(MBE1_PAR) <= '1';
                        exception_hold := '0';
                        datapar_error_count <= datapar_error_count + 1;
                end if;
            end if;
                
            -- catch the write signal from the PCI bus.
            if set_wrtmp = '1' then
                wrtmp_valid <= '1';
            end if;
                
            -- handle register writes from the PCI9054. We do this here so it
            -- doesn't interfere with write from the Massbus.
            if wrtmp_valid = '1' then
                case write_reg is
                    when REG_COMMAND => -- command_reg
                        command_reg(conv_integer(write_drive))(5 downto 1) <= write_temp(5 downto 1);
                        command_reg(conv_integer(write_drive))(MBC_GO) <= '0';
                        command_reg(conv_integer(write_drive))(MBC_DRY) <= '1';
                    when REG_STATUS =>
                        status_reg(conv_integer(write_drive))( 14 downto 0) <= write_temp(14 downto 0);
                        if write_temp(7) = '1' then
                            occupied <= OCC_FALSE;
                        end if;
                        if status_reg(conv_integer(write_drive))(MBS_MOL) /= write_temp(MBS_MOL) then
                            -- clear VV and set ATA
                            status_reg(conv_integer(write_drive))(MBS_VV) <= '0';
                            media_change_attn(conv_integer(write_drive)) := '1';
                        end if;
                    when REG_ERROR1 =>
                        error1_reg(conv_integer(write_drive)) <= write_temp;
                    when REG_MAINT =>
                        maint_reg <= write_temp;
                    when REG_ATTENTION =>
                        attsum_reg <= write_temp;
                    when REG_TRKSEC =>
                        trksec_reg(conv_integer(write_drive)) <= write_temp;
                    when REG_DRVTYPE =>
                        drvtype_reg(conv_integer(write_drive)) <= write_temp;
                    when REG_LOOKAHD =>
                        lookahd_reg <= write_temp;
                    when REG_SERNUM =>
                        sernum_reg(conv_integer(write_drive)) <= write_temp;
                    when REG_OFFSET =>
                        offset_reg <= write_temp;
                    when REG_DESCYL => -- descyl_reg
                        descyl_reg(conv_integer(write_drive)) <= write_temp;
                    when REG_CURCYL =>
                        curcyl_reg(conv_integer(write_drive)) <= write_temp;
                    when REG_ERROR2 =>
                        error2_reg <= write_temp;
                    when REG_ERROR3 =>
                        error3_reg <= write_temp;
                    when REG_ECC1 =>
                        ecc1_reg <= write_temp;
                    when REG_ECC2 =>
                        ecc2_reg <= write_temp;
                    when others =>
                end case;
                wrtmp_valid <= '0';
            end if;
            
            if counter_temp_valid = '1' then
                if counter_temp_reg = "0001100000000000" then
                    ctlpar_error_count <= counter_temp;
                elsif counter_temp_reg = "0001100000000100" then
                    datapar_error_count <= counter_temp;
                elsif counter_temp_reg(15 downto 5) = "00011100000" then
                    block_read_count(conv_integer(counter_temp_reg(4 downto 2))) <= counter_temp;
                elsif counter_temp_reg(15 downto 5) = "00100000000" then
                    block_write_count(conv_integer(counter_temp_reg(4 downto 2))) <= counter_temp;
                end if;
            end if;
                            
            if drives_online(conv_integer(massbus_DS)) = '1' or massbus_RS = REG_ATTENTION then
                send_command <= cmd_fifo_write;
                transfer := demand;
                massbus_TRA <= demand;
            else
                send_command <= '0';
                transfer := '0';
                massbus_TRA <= '0';
            end if;
            
            -- calculate the attention bit...
            for i in 7 downto 0 loop
                attention(i) := '0';  -- shouldn't be necessary
                attention(i) := error1_reg(i)(15) or error1_reg(i)(14) or error1_reg(i)(13) or error1_reg(i)(12) or
                                error1_reg(i)(11) or error1_reg(i)(10) or error1_reg(i)(9)  or error1_reg(i)(8)  or
                                error1_reg(i)(7)  or error1_reg(i)(6)  or error1_reg(i)(5)  or error1_reg(i)(4)  or
                                error1_reg(i)(3)  or error1_reg(i)(2)  or error1_reg(i)(1)  or error1_reg(i)(0)  or
                                error2_reg(15) or error2_reg(14) or error2_reg(13) or error2_reg(12) or
                                error2_reg(11) or error2_reg(10) or error2_reg(9)  or error2_reg(8)  or
                                error2_reg(7)  or error2_reg(6)  or error2_reg(5)  or error2_reg(4)  or
                                error2_reg(3)  or error2_reg(2)  or error2_reg(1)  or error2_reg(0)  or
                                error3_reg(15) or error3_reg(14) or error3_reg(13) or error3_reg(12) or
                                error3_reg(11) or error3_reg(10) or error3_reg(9)  or error3_reg(8)  or
                                error3_reg(7)  or error3_reg(6)  or error3_reg(5)  or error3_reg(4)  or
                                error3_reg(3)  or error3_reg(2)  or error3_reg(1)  or error3_reg(0) or
                                seek_delay_attn(i) or media_change_attn(i);
            end loop;
                         
            massbus_EXC <= not exception_hold;
            
            -- Move the attention bits into the register bits
            attn_drive0 <= attention(0);
            attn_drive1 <= attention(1);
            attn_drive2 <= attention(2);
            attn_drive3 <= attention(3);
            attn_drive4 <= attention(4);
            attn_drive5 <= attention(5);
            attn_drive6 <= attention(6);
            attn_drive7 <= attention(7);
            
            massbus_ATTN <= attn_drive7 or attn_drive6 or
                            attn_drive5 or attn_drive4 or
                            attn_drive3 or attn_drive2 or
                            attn_drive1 or attn_drive0;
                            
        end if; -- clock tick

	end process;
	
-- process to clock the leds so they meet timing
    ledproc: process (LCLK)
        variable toggle: std_logic;
    begin
    
        if LCLK'event and LCLK = '1' then
--            LEDS(0) <= not drives_online(7);  
--            LEDS(1) <= not drives_online(6);
--            LEDS(2) <= not drives_online(5); 
--            LEDS(3) <= not drives_online(4);
--            LEDS(4) <= not drives_online(3);
--            LEDS(5) <= not drives_online(2);
--            LEDS(6) <= not drives_online(1);
--            LEDS(7) <= not drives_online(0);
            LEDS(0) <= massbus_RUN;  
            toggle := not toggle;
--            LEDS(1) <= topc_ready_n;
            LEDS(1) <= toggle;
            LEDS(2) <= not command_reg(conv_integer(massbus_DS))(5); 
            LEDS(3) <= not command_reg(conv_integer(massbus_DS))(4);
            LEDS(4) <= not command_reg(conv_integer(massbus_DS))(3);
            LEDS(5) <= not command_reg(conv_integer(massbus_DS))(2);
            LEDS(6) <= not command_reg(conv_integer(massbus_DS))(1);
            LEDS(7) <= not command_reg(conv_integer(massbus_DS))(0);
        end if;
    end process;
    
-- This is the process to handle the PCI bus transactions
	pcibus: process (LCLK)

	begin       
        if LCLK'event and LCLK = '1' then
            counter_temp_valid <= '1';

            -- do the address and cycle logic
	  		if PCI_ADS = '0' then
    			pci_bus_address <= PCI_LAD(15 downto 0); -- catch a new address
    			pci_cycle_in_process <= '1';
    			
    			-- wait for the command fifo
    			if PCI_LAD(15 downto 8) = "00010000" and PCI_LW_R = '0' then
    			    if command_ready_n = '0' then
                        command_fifo_read <= '1';
                        cmdrdy <= '1';
                    else
                        command_fifo_read <= '0';
                        cmdrdy <= '0';
                    end if;
                elsif PCI_LAD(15) = '1' and PCI_LW_R = '0' then
                    if topc_ready_n = '0' then
                        topc_fifo_read <= '1'; 
                        datardy <= '1';
                    else
                        topc_fifo_read <= '0'; 
                        datardy <= '0';
                    end if;
                    cmdrdy <= '0';
    			else
                    command_fifo_read <= '0';
                    topc_fifo_read <= '0';
                    datardy <= '0';
                    cmdrdy <= '0';
    			end if;
    		else -- not first cycle of transfer
   		        if PCI_READY = READY_TRUE then
   		            pci_cycle_in_process <= '0';  
   		        end if;
                
                command_fifo_read <= '0';
                topc_fifo_read <= '0';
			end if;
			
			-- Write the registers, reads happen in their own process
            if pci_cycle_in_process = '1' and PCI_LW_R = '1' and PCI_READY = READY_TRUE then
                if pci_bus_address(15 downto 10) = "000000" then
                    -- drive registers
                    -- write them...
                    write_temp <= PCI_LAD(15 downto 0);
                    write_reg <= pci_bus_address(6 downto 2);
                    write_drive <= pci_bus_address(9 downto 7);
                    frompc_fifo_write <= '0';
                    set_wrtmp <= '1';
                elsif pci_bus_address(15 downto 0) = "0000010000000000" then
                    -- drives online register
                    drives_online <= PCI_LAD(7 downto 0);
                    frompc_fifo_write <= '0';
                    set_wrtmp <= '0';
                elsif pci_bus_address(15 downto 0) = "0000100000000000" then 
                    -- data clock divisor register
                    sclk_max_count <= PCI_LAD(10 downto 0);
                    frompc_fifo_write <= '0';
                    set_wrtmp <= '0';
                elsif pci_bus_address(15 downto 0) = "0000110000000000" then 
                    -- transfer delay register
                    delay_max_reg <= PCI_LAD(7 downto 0);
                    frompc_fifo_write <= '0';
                    set_wrtmp <= '0';
                elsif pci_bus_address(15 downto 6) = "0001010000" then 
                    -- Drive characteristics register
                    sectors_per_track(conv_integer(pci_bus_address(4 downto 2))) <= PCI_LAD(7 downto 0);
                    heads_per_cyl(conv_integer(pci_bus_address(4 downto 2))) <= PCI_LAD(15 downto 8);
                    number_of_cyls(conv_integer(pci_bus_address(4 downto 2))) <= PCI_LAD(30 downto 16);
                    frompc_fifo_write <= '0';
                    set_wrtmp <= '0';
                elsif pci_bus_address(15 downto 0) = "0001100000000000" or
                      pci_bus_address(15 downto 0) = "0001110000000000" or
                      pci_bus_address(15 downto 0) = "0010000000000000" then
                    -- Counters
                    counter_temp <= PCI_LAD(19 downto 0);
                    counter_temp_reg <= pci_bus_address;
                    counter_temp_valid <= '1';
                    frompc_fifo_write <= '0';
                    set_wrtmp <= '0';
                elsif pci_bus_address(15) = '1' then
                    -- Data transfer fifo
                    frompc_fifo_write <= '1';
                    frompc_fifo_wr_data <= PCI_LAD(17 downto 0); 
                    set_wrtmp <= '0';
                else
                    frompc_fifo_write <= '0';
                end if;
            else
                frompc_fifo_write <= '0';
                set_wrtmp <= '0';
            end if;
        end if;

	end process;
	
-- Process to run the pci bus outputs from control signals as opposed to clocks
	pci_out_proc: process (pci_cycle_in_process, 
	                       pci_bus_address,
	                       command_fifo_rd_data,
	                       topc_fifo_rd_data,
	                       command_reg,
	                       cmdrdy,
	                       datardy,
	                       datapar_error_count,
	                       ctlpar_error_count,
	                       delay_max_reg,
	                       PCI_LW_R,
	                       status_reg,
	                       error1_reg,
	                       maint_reg,
	                       attsum_reg,
	                       trksec_reg,
	                       drvtype_reg,
	                       lookahd_reg,
	                       sernum_reg,
	                       offset_reg,
	                       descyl_reg,
	                       curcyl_reg,
	                       error2_reg,
	                       error3_reg,
	                       ecc1_reg,
	                       ecc2_reg,
	                       drives_online,
	                       sclk_max_count,
	                       block_read_count,
	                       block_write_count)
        variable outreg: std_logic_vector(30 downto 0);
	begin
        if pci_cycle_in_process = '1' and PCI_LW_R = '0' then
            if pci_bus_address(15 downto 10) = "000000" then
                -- drive registers
                -- read them
                case pci_bus_address(6 downto 2) is
                    when "00000" =>
                        outreg := "000000000000000" & command_reg(conv_integer(pci_bus_address(9 downto 7)));
                    when "00001" =>
                        outreg := "000000000000000" & status_reg(conv_integer(pci_bus_address(9 downto 7)));
                    when "00010" =>
                        outreg := "000000000000000" & error1_reg(conv_integer(pci_bus_address(9 downto 7)));
                    when "00011" =>
                        outreg := "000000000000000" & maint_reg;
                    when "00100" =>
                        outreg := "000000000000000" & attsum_reg;
                    when "00101" =>
                        outreg := "000000000000000" & trksec_reg(conv_integer(pci_bus_address(9 downto 7)));
                    when "00110" =>
                        outreg := "000000000000000" & drvtype_reg(conv_integer(pci_bus_address(9 downto 7)));
                    when "00111" =>
                        outreg := "000000000000000" & lookahd_reg;
                    when "01000" =>
                        outreg := "000000000000000" & sernum_reg(conv_integer(pci_bus_address(9 downto 7)));
                    when "01001" =>
                        outreg := "000000000000000" & offset_reg;
                    when "01010" =>
                        outreg := "000000000000000" & descyl_reg(conv_integer(pci_bus_address(9 downto 7)));
                    when "01011" =>
                        outreg := "000000000000000" & curcyl_reg(conv_integer(pci_bus_address(9 downto 7)));
                    when "01100" =>
                        outreg := "000000000000000" & error2_reg;
                    when "01101" =>
                        outreg := "000000000000000" & error3_reg;
                    when "01110" =>
                        outreg := "000000000000000" & ecc1_reg;
                    when "01111" =>
                        outreg := "000000000000000" & ecc2_reg;
                    when others =>
                        outreg := "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ";
                end case;
            elsif pci_bus_address(15 downto 8) = "00000100" then            -- 0x0400
                outreg := "0000000000000000000000" & massbus_FAIL & drives_online;
            elsif pci_bus_address(15 downto 8) = "00001000" then            -- 0x0800
                outreg := "00000000000000000000" & sclk_max_count;
            elsif pci_bus_address(15 downto 8) = "00001100" then            -- 0x0c00
                outreg := "00000000000000000000000" & delay_max_reg;
            elsif pci_bus_address(15 downto 8) = "00010000" then            -- 0x1000
                outreg := command_fifo_rd_data(30 downto 0);
            elsif pci_bus_address(15 downto 8) = "00010100" then            -- 0x1400
                outreg := number_of_cyls(conv_integer(pci_bus_address(4 downto 2)))(14 downto 0) &
                          heads_per_cyl(conv_integer(pci_bus_address(4 downto 2))) &
                          sectors_per_track(conv_integer(pci_bus_address(4 downto 2)));
            elsif pci_bus_address(15 downto 8) = "00011000" then            -- 0x1800
                case pci_bus_address(4 downto 2) is
                    when "000" =>
                        outreg := "00000000000" & ctlpar_error_count;
                    when "001" =>
                        outreg := "00000000000" & datapar_error_count;
                    when "100" =>
                        outreg := "000000000000000" & conv_std_logic_vector(MAJOR_REVISION,8) & conv_std_logic_vector(MINOR_REVISION,8);
                    when others =>
                        outreg := "0000000000000000000000000000000";
                end case;
            elsif pci_bus_address(15 downto 8) = "00011100" then            -- 0x1c00
                outreg := "00000000000" &  block_read_count(conv_integer(pci_bus_address(4 downto 2)));
            elsif pci_bus_address(15 downto 8) = "00100000" then            -- 0x2000
                outreg := "00000000000" &  block_write_count(conv_integer(pci_bus_address(4 downto 2)));
            elsif pci_bus_address(15) = '1' then                            -- 0x8000
                outreg := "0000000000000" & topc_fifo_rd_data;
            else
                outreg := "0000000000000000000000000000000";
            end if;
            
            -- connect up the data...
            if pci_bus_address(15 downto 8) = "00010000" then 
                PCI_LAD_OUT <= cmdrdy & outreg;
            elsif pci_bus_address(15) = '0' then
                PCI_LAD_OUT <= '0' & outreg;
            else
                PCI_LAD_OUT <= datardy & outreg;
            end if;
        else
            PCI_LAD_OUT <= "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ";
        end if;
	end process;

-- Handle the write data for the disk	
	datawrite :  process (LCLK)
	    variable dbus_parity: std_logic;
	begin       
        if LCLK'event and LCLK = '1' and massbus_FAIL = '0' then
            -- delay massbus_WCLK for edge detection
            wclk_delayed <= massbus_WCLK;
            
            -- calculate databus parity...
            dbus_parity := massbus_D(17) xor massbus_D(16) xor massbus_D(15) xor massbus_D(14) xor
                           massbus_D(13) xor massbus_D(12) xor massbus_D(11) xor massbus_D(10) xor
                           massbus_D(9) xor massbus_D(8) xor massbus_D(7) xor massbus_D(6) xor
                           massbus_D(5) xor massbus_D(4) xor massbus_D(3) xor massbus_D(2) xor
                           massbus_D(1) xor massbus_D(0) xor massbus_DPA;
            
            if command_reg(conv_integer(active_drive))(5 downto 3) = WRITE_DATA_CMDS and catch_wr_data = '1' then
                -- look for the falling edge since it comes back inverted
                --  from what we send out as SCLK
                if massbus_WCLK = '0' and wclk_delayed = '1' then   
                    topc_fifo_write <= '1';
                    topc_fifo_wr_data <= massbus_D;
                    if dbus_parity = '0' then
                        set_wrdata_error <= '1';
                    else
                        set_wrdata_error <= '0';
                    end if;
                else
                    topc_fifo_write <= '0';
                    set_wrdata_error <= '0';
                end if;
            else
                topc_fifo_write <= '0';
                set_wrdata_error <= '0';
            end if;
        end if;
	end process;

    PCI_INT <= command_ready_n;

-- the command fifo holds commands from the RH controller to the
--  logical drive. These end up going to the host PC.
-- Only commands with the least significant bit set will be sent
--  up to the host PC.

	command_fifo: fifo_generator_v9_3_36
    PORT MAP (
        clk => LCLK,
        rst => not RESET,
        din => command_fifo_wr_data,
        wr_en => send_command,
        rd_en => command_fifo_read,
        dout => command_fifo_rd_data,
--        full => full,
--        almost_full => almost_full,
        empty => command_ready_n
    );

    datafifo_reset <= not RESET or re_init or command_clear;
    
-- To PC fifo holds data being written to our imaginary Disk.

	topc_fifo : fifo_generator_v9_3
    PORT MAP (
        clk => LCLK,
        rst => datafifo_reset,
        din => topc_fifo_wr_data,
        wr_en => topc_fifo_write,
        rd_en => topc_fifo_read,
        dout => topc_fifo_rd_data,
--        full => full,
--        almost_full => almost_full,
        empty => topc_ready_n
    );

-- From PC fifo holds data being read from our imaginary disk.

	frompc_fifo : fifo_generator_v9_3
    PORT MAP (
        clk => LCLK,
        rst => datafifo_reset,
        din => frompc_fifo_wr_data,
        wr_en => frompc_fifo_write,
        rd_en => frompc_fifo_read,
        dout => frompc_fifo_rd_data,
--        full => full,
--        almost_full => almost_full,
        empty => frompc_ready_n
    );

--    massbus_OCC <= '1';
    massbus_OCC <= occupied;
	
end behavioral;
