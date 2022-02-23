-- ****************************************************************************
-- *
-- * Licensed Materials - Property of IBM
-- * 5698-WSH
-- *
-- * (C) Copyright IBM Corp. 2004 - 2015.  All Rights Reserved.
-- *		
-- * US Government Users Restricted Rights - Use, duplication or
-- * disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
-- *
-- ****************************************************************************

-------------------------------------------------------------------------------
-- Create database
-------------------------------------------------------------------------------

CREATE DATABASE HWAMDM
USING CODESET UTF-8 TERRITORY US
COLLATE USING IDENTITY
WITH 'HWAMDM Database';

UPDATE DB CFG FOR HWAMDM USING LOGBUFSZ 512;
UPDATE DB CFG FOR HWAMDM USING LOGFILSIZ 1000;
UPDATE DB CFG FOR HWAMDM USING LOGPRIMARY 40;
UPDATE DB CFG FOR HWAMDM USING LOGSECOND 20;
UPDATE DB CFG FOR HWAMDM USING LOCKTIMEOUT 180;
UPDATE DB CFG FOR HWAMDM USING LOCKLIST 8192;
UPDATE DB CFG FOR HWAMDM USING APP_CTL_HEAP_SZ 1024;
UPDATE DB CFG FOR HWAMDM USING DFT_QUERYOPT 3;
UPDATE DB CFG FOR HWAMDM USING AUTO_MAINT ON;
UPDATE DB CFG FOR HWAMDM USING AUTO_TBL_MAINT ON;
UPDATE DB CFG FOR HWAMDM USING AUTO_RUNSTATS ON;
UPDATE DB CFG FOR HWAMDM USING STMT_CONC LITERALS;
UPDATE DB CFG FOR HWAMDM USING CATALOGCACHE_SZ -1;
UPDATE DB CFG FOR HWAMDM USING PAGE_AGE_TRGT_MCR 120;
UPDATE DB CFG FOR HWAMDM USING LOCKLIST AUTOMATIC;
