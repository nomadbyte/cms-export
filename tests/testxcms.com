$!===========================================================================
$ THIS_FILE = f$elem(0,";",f$env("procedure"))
$ USAGE_ARGS = ""
$ PRJ_NAME = "XCMS"
$ THIS_FACILITY = "TEST''PRJ_NAME'"
$ VERSION = "0.8.0"
$ COPYRIGHT = "Copyright (c) 2015, Artur Shepilko, <cms-export@nomadbyte.com>."
$!---------------------------------------------------------------------------
$! For Usage -- run with ? (?? for usage details and license)
$! License listed at the bottom.
$!===========================================================================
$!
$ USAGE = f$parse(THIS_FILE,,,"NAME") + f$parse(THIS_FILE,,,"TYPE") -
  + " " + USAGE_ARGS
$
$ verify = f$trnlnm("VERIFY_''THIS_FACILITY'")
$ saveVerify = f$verify(verify)
$
$ ON ERROR THEN GOTO ERROR
$ ON CONTROL_Y THEN GOTO ERROR
$ ON CONTROL_C THEN GOTO ERROR
$ defaultDir = f$env("DEFAULT")
$
$ gosub GOSUB_SETUP_LOGGING
$
$ STS_SUCCESS = "%X10000001"
$ STS_ERROR = "%X10000002"
$
$ DEFAULT_CMSLIB = "[.testlib]"
$
$ DEFAULT_TEST_LIST = "commits classes"
$ TEST_LIST_commits = "T01 T02 T03 T04 T05 T06 T07 T08 T09 T10" -
    + " T11 T12 T13 T14 T15"
$ TEST_LIST_classes = "T16 T17 T18 T19"
$
$ sts = STS_ERROR
$
$GET_ARGS:
$ if (f$extr(0,1,p1) .eqs. "?") then goto USAGE
$
$ cmsLib = DEFAULT_CMSLIB
$ cmsLib = f$parse(cmsLib,,,,"SYNTAX_ONLY") - ".;"
$ if (cmsLib .eqs. "" -
      .or. f$parse(cmsLib,,,"NAME") .nes. "")
$ then
$   cmsLib = ""
$   goto ERROR
$ endif
$
$ cmsLibName =  f$edit(cmsLib,"LOWERCASE") - "]" -
    - f$edit( f$parse(cmsLib - "]" + ".-]")  - "].;", "LOWERCASE" ) - "."
$
$ testList = f$edit("''p1' ''p2' ''p3' ''p4' ''p5' ''p6'","TRIM,LOWERCASE")
$ if (testList .eqs. "") then testList = DEFAULT_TEST_LIST
$
$!----------------------------------
$ CHAR_SPACE = " " !!space
$ CHAR_MINUS = "-" !!minus
$
$ call RUN_TESTS "''testList'"
$
$ sts = STS_SUCCESS
$
$EXIT:
$ exit 'sts' + (0 * f$verify(saveVerify))

$USAGE:
$ logmsg "I|COPYRIGHT:", COPYRIGHT
$ logmsg "I|VERSION:", VERSION
$ logmsg "I|USAGE:", USAGE
$ logmsg "I|DEFAULT_TEST_LIST:", DEFAULT_TEST_LIST
$
$ logmsg "I|HELP:Run with ?? for usage details and license."
$ if (f$extr(0,2,p1) .eqs. "??") then call USAGE_DETAILS
$ goto EXIT

$ERROR:
$ exit 'sts' + (0 * f$verify(saveVerify))

$!-------------------------------
$GOSUB_SETUP_LOGGING:
$!
$ dbg = "!"
$ dbg2 = "!"
$ dbgLvl = f$trnlnm("DBG_''THIS_FACILITY'")
$ if (dbgLvl .nes. "" .and f$int(dbgLvl) .gt. 0) then dbg = ""
$ if (f$int(dbgLvl) .gt. 1) then dbg2 = ""
$!
$ dbgmsg = "''dbg'write dbg_output THIS_FACILITY,""-"","
$ dbgmsg2 = dbg2 + dbgmsg
$ dbgtrace = dbgmsg + """DBG|TRACE:"","
$
$ logmsg = "write log_output THIS_FACILITY,""-"","
$ errmsg = "write err_output THIS_FACILITY,""-"","
$!
$ if (f$trnlnm("log_output") .eqs. "") then -
    def /nolog log_output sys$output
$!
$ if (f$trnlnm("err_output") .eqs. "") then -
    def /nolog err_output sys$error
$
$ if (dbg .nes. "!" .and. f$trnlnm("dbg_output") .eqs. "") then -
    def /nolog dbg_output log_output
$!
$ return  !GOSUB_SETUP_LOGGING


$!============================================================================
$RUN_TESTS: subroutine
$
$ sts = STS_ERROR
$
$ STS_SEARCH_NOMATCHES = "%X08D78053"
$ groupTestList = f$edit(p1,"TRIM,COMPRESS")
$
$ testsRun = 0
$ testsDisabled = 0
$ testsFailed = 0
$
$ gosub GOSUB_SETUP
$
$ gtid = 0
$DO_GROUP:
$   groupTest = f$elem(gtid,CHAR_SPACE, groupTestList)
$   if (groupTest .eqs. CHAR_SPACE) then goto ENDDO_GROUP
$   if (groupTest .eqs. "") then goto NEXT_GROUP
$
$   if (f$extr(0,1,groupTest) .eqs. CHAR_MINUS)
$   then
$     testsDisabled = testsDisabled + 1
$     groupTest = groupTest - CHAR_MINUS
$     logmsg "W|TEST_DISABLED:", groupTest
$     goto NEXT_GROUP
$   endif
$
$   testList = ""
$   if (f$type(TEST_LIST_'groupTest') .nes. "") -
      then testList = f$edit(TEST_LIST_'groupTest',"COMPRESS")
$
$   if (testList .eqs. "") then testList = groupTest
$
$   tid = 0
$DO_TEST:
$   test = f$elem(tid,CHAR_SPACE, testList)
$   if (test .eqs. CHAR_SPACE) then test = groupTest
$   if (test .eqs. "") then goto NEXT_TEST
$
$   if (f$extr(0,1,test) .eqs. CHAR_MINUS)
$   then
$     testsDisabled = testsDisabled + 1
$     test = test - CHAR_MINUS
$     logmsg "W|TEST_DISABLED:", test
$     goto NEXT_TEST
$   endif
$
$   logmsg "I|TEST:", test
$
$   testsRun = testsRun + 1
$
$   testPassed = "F"
$   gosub GOSUB_TST_'test'
$
$   if (.not. testPassed)
$   then
$     testsFailed = testsFailed + 1
$     errmsg "E|FAILED:",test
$   else
$     logmsg "I|PASSED:",test
$   endif
$
$NEXT_TEST:
$   if (test .eqs. groupTest) then goto ENDDO_TEST
$   tid = tid + 1
$   goto DO_TEST
$ENDDO_TEST:
$
$NEXT_GROUP:
$   gtid = gtid + 1
$   goto DO_GROUP
$ENDDO_GROUP:
$
$EXIT:
$ if (testsFailed .eq. 0) then sts = STS_SUCCESS
$
$ gosub GOSUB_TEARDOWN
$ logmsg "I|TESTSTOTAL RUN:", testsRun, " DISABLED:", testsDisabled -
                   , " FAILED:", testsFailed
$
$ exit 'sts' !RUN_TESTS

$ERROR:
$ goto EXIT

$!-------------------------------
$GOSUB_SETUP:
$ logmsg "I|SETUP:", cmsLibName, " ", cmsLib
$ if (f$parse(cmsLib) .eqs. "")
$ then
$   create /dir 'cmsLib'
$   cms create lib 'cmsLib'  !! ODS5: /ext /long
$ endif
$
$ cms set lib 'cmsLib'
$
$ EXPORTCMS := @BLDROOT:[bin]exportcms-git.com
$
$ return !GOSUB_SETUP

$!-------------------------------
$GOSUB_TEARDOWN:
$ logmsg "I|TEARDOWN"
$
$ return !GOSUB_SETUP


$!-------------------------------
$GOSUB_WAIT:
$ DEFAULT_WAIT_INTERVAL = "00:00:01" !! 1 sec, NOWAIT = "0"
$
$ if (f$type(waitInterval) .eqs. "") then waitInterval = ""
$ if (waitInterval .eqs. "") then waitInterval = DEFAULT_WAIT_INTERVAL
$
$ wait 'waitInterval'
$
$ waitInterval = ""
$ return !GOSUB_WAIT


$!-------------------------------
$GOSUB_MATCH_GITFAST:
$
$ gitfastMatchEQ = "F"
$
$ diff /SLP  'gitfastMatchFile' 'gitfastFile' /out='gitfastDifFile'
$
$ STS_SEARCH_NOMATCHES = "%X08D78053"
$
$ set noon
$ search 'gitfastDifFile' "-" /key=(pos:1,size:1) -
  ,"/" /key=(pos:1,size:1) -
  ,"committer" /key=(pos:1,siz:9) -
  ,"tagger" /key=(pos:1,siz:6) -
  /match=NOR /nowarn /noout
$
$ stsSearch = $STATUS
$ set on
$
$ gitfastMatchEQ = (stsSearch .eq. STS_SEARCH_NOMATCHES)
$
$ return !GOSUB_MATCH_GITFAST


$!-------------------------------
$GOSUB_INIT_EXPORTCMS:
$
$ xcmsLibPath = ""
$ xcmsOutFile = ""
$ xcmsElemList = ""
$ xcmsClassList = ""
$ xcmsClassBranchXrefFile = ""
$
$ return !GOSUB_INIT_EXPORTCMS

$!-------------------------------
$GOSUB_TEST_EXPORTCMS:
$ testPassed = "F"
$
$ xcmsOutFile = f$parse(testTag,"[].git-fast",,,"SYNTAX_ONLY")
$
$ EXPORTCMS "''xcmsLibPath'" 'xcmsOutFile' "''xcmsElemList'" "''xcmsClassList'" -
    "''xcmsClassBranchXrefFile'"
$
$ gitfastFile = xcmsOutFile
$ gitfastMatchFile = f$parse(testTag,"[.data].git-fast",,,"SYNTAX_ONLY")
$ gitfastDifFile = f$parse(test, ".dif",,,"SYNTAX_ONLY") - ";"
$
$ gosub GOSUB_MATCH_GITFAST
$ testPassed = gitfastMatchEQ
$
$ testStatus = "FAILED"
$ if (testPassed) then testStatus = "PASSED"
$
$ testStatusFile = gitfastDifFile + "_''testStatus'"
$ rename /nolog/noconf 'gitfastDifFile' 'testStatusFile'
$
$ return !GOSUB_TEST_EXPORTCMS


$!-------------------------------
$GOSUB_TST_commits:$ testName = "allCommits"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "T"
$ return


$!-------------------------------
$GOSUB_TST_classes:$ testName = "allClasses"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "T"
$ return


$!-------------------------------
$GOSUB_TST_T01:$ testName = "emptyLib"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- use empty CMS library
$ continue
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T02:$ testName = "oneElem"
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- create new file and add new CMS element
$ create elem1.txt
elem1.txt
$EOD
$
$ cms create elem elem1.txt "''testTag'"
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T03:$ testName = "genTwo"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- update an exisiting file
$
$ cms reserve elem1.txt ""
$ pipe write sys$output testTag | append sys$input elem1.txt
$
$ cms replace /if elem1.txt "''testTag'"
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T04:$ testName = "oneElemMainline"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- multiple updates to an existing elem
$
$ cms reserve elem1.txt "''testTag':1"
$ pipe write sys$output "''testTag':1" | append sys$input elem1.txt
$ cms replace /if elem1.txt "''testTag':1"
$ gosub GOSUB_WAIT
$
$ cms reserve elem1.txt "''testTag':2"
$ pipe write sys$output "''testTag':2" | append sys$input elem1.txt
$ cms replace /if elem1.txt "''testTag':2"
$ gosub GOSUB_WAIT
$
$ cms reserve elem1.txt "''testTag':3"
$ pipe write sys$output "''testTag':3" | append sys$input elem1.txt
$ cms replace /if elem1.txt "''testTag':3"
$ gosub GOSUB_WAIT
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T05:$ testName = "oneVariant_A"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- create a variant generation
$
$ cms reserve elem1.txt "''testTag'"
$ pipe write sys$output "''testTag'" | append sys$input elem1.txt
$ cms replace /if elem1.txt /VAR=A "''testTag'"
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T06:$ testName = "oneElemVarline_A"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- multiple updates to variant generation line
$
$ elem1_varline = "5A"
$ elem1_varGen = 1
$ elem1_GEN = elem1_varline + f$str(elem1_varGen)  !! TOADD:use class
$
$ cms reserve elem1.txt /GEN='elem1_GEN' "''testTag':1"
$ pipe write sys$output "''testTag':1" | append sys$input elem1.txt
$ cms replace /if elem1.txt "''testTag':1"
$ gosub GOSUB_WAIT
$
$ elem1_varGen = elem1_varGen + 1
$ elem1_GEN = elem1_varline + f$str(elem1_varGen)  !! TOADD:use class
$ cms reserve elem1.txt /GEN='elem1_GEN' "''testTag':2"
$ pipe write sys$output "''testTag':2" | append sys$input elem1.txt
$ cms replace /if elem1.txt "''testTag':2"
$ gosub GOSUB_WAIT
$
$ elem1_varGen = elem1_varGen + 1
$ elem1_GEN = elem1_varline + f$str(elem1_varGen)  !! TOADD:use class
$ cms reserve elem1.txt /GEN='elem1_GEN' "''testTag':3"
$ pipe write sys$output "''testTag':3" | append sys$input elem1.txt
$ cms replace /if elem1.txt "''testTag':3"
$ gosub GOSUB_WAIT
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T07:$ testName = "oneElemManyVarlines"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- multiple updates to multiple variant generation lines
$
$ elem1_startGEN = "3"
$ elem1_VAR = "F"
$ elem1_varline = elem1_startGEN + elem1_VAR
$ elem1_varGen = 1
$ elem1_GEN = elem1_varline + f$str(elem1_varGen)  !! TOADD:use class
$
$ cms reserve elem1.txt /GEN='elem1_startGEN' "''testTag':1"
$ pipe write sys$output "''testTag':1" | append sys$input elem1.txt
$ cms replace /if elem1.txt /VAR='elem1_VAR' "''testTag':1"
$ gosub GOSUB_WAIT
$
$ cms reserve elem1.txt /GEN='elem1_GEN' "''testTag':2"
$ pipe write sys$output "''testTag':2" | append sys$input elem1.txt
$ cms replace /if elem1.txt "''testTag':2"
$ gosub GOSUB_WAIT
$
$ elem1_varGen = elem1_varGen + 1
$ elem1_GEN = elem1_varline + f$str(elem1_varGen)  !! TOADD:use class
$ cms reserve elem1.txt /GEN='elem1_GEN' "''testTag':3"
$ pipe write sys$output "''testTag':3" | append sys$input elem1.txt
$ cms replace /if elem1.txt "''testTag':3"
$ gosub GOSUB_WAIT
$
$
$ elem1_startGEN = "5"
$ elem1_VAR = "T"
$ elem1_varline = elem1_startGEN + elem1_VAR
$ elem1_varGen = 1
$ elem1_GEN = elem1_varline + f$str(elem1_varGen)  !! TOADD:use class
$
$ cms reserve elem1.txt /GEN='elem1_startGEN' "''testTag':4"
$ pipe write sys$output "''testTag':4" | append sys$input elem1.txt
$ cms replace /if elem1.txt /VAR='elem1_VAR' "''testTag':4"
$ gosub GOSUB_WAIT
$
$ cms reserve elem1.txt /GEN='elem1_GEN' "''testTag':5"
$ pipe write sys$output "''testTag':5" | append sys$input elem1.txt
$ cms replace /if elem1.txt "''testTag':5"
$ gosub GOSUB_WAIT
$
$ elem1_varGen = elem1_varGen + 1
$ elem1_GEN = elem1_varline + f$str(elem1_varGen)  !! TOADD:use class
$ cms reserve elem1.txt /GEN='elem1_GEN' "''testTag':6"
$ pipe write sys$output "''testTag':6" | append sys$input elem1.txt
$ cms replace /if elem1.txt "''testTag':6"
$ gosub GOSUB_WAIT
$
$ !!-- more updates to an already existing varline
$ !!--
$ elem1_varline = "3F"
$ elem1_varGen = 3
$ elem1_GEN = elem1_varline + f$str(elem1_varGen)  !! TOADD:use class
$
$ gosub GOSUB_WAIT
$ cms reserve elem1.txt /GEN='elem1_GEN' "''testTag':7"
$ pipe write sys$output "''testTag':7" | append sys$input elem1.txt
$ cms replace /if elem1.txt "''testTag':7"
$ gosub GOSUB_WAIT
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T08:$ testName = "variantVarline_V"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- create and update variant of a variant generation
$
$ elem1_startGEN = "5A2"
$ elem1_VAR = "V"
$ elem1_varline = elem1_startGEN + elem1_VAR
$ elem1_varGen = 1
$ elem1_GEN = elem1_varline + f$str(elem1_varGen)  !! TOADD:use class
$
$ cms reserve elem1.txt /GEN='elem1_startGEN' "''testTag':1"
$ pipe write sys$output "''testTag':1" | append sys$input elem1.txt
$ cms replace /if elem1.txt /VAR='elem1_VAR' "''testTag':1"
$ gosub GOSUB_WAIT
$
$ cms reserve elem1.txt /GEN='elem1_GEN' "''testTag':2"
$ pipe write sys$output "''testTag':2" | append sys$input elem1.txt
$ cms replace /if elem1.txt "''testTag':2"
$ gosub GOSUB_WAIT
$
$ elem1_varGen = elem1_varGen + 1
$ elem1_GEN = elem1_varline + f$str(elem1_varGen)  !! TOADD:use class
$ cms reserve elem1.txt /GEN='elem1_GEN' "''testTag':3"
$ pipe write sys$output "''testTag':3" | append sys$input elem1.txt
$ cms replace /if elem1.txt "''testTag':3"
$ gosub GOSUB_WAIT
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T09:$ testName = "manyElems"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- add more elements
$
$ elemName = "elem2.txt"
$ pipe write sys$output elemName > 'elemName'
$
$ elemName = "elem3.txt"
$ pipe write sys$output elemName > 'elemName'
$
$ !!-- NOTE: elements may receive the same time-stamp when created via wild-card
$ !!--   elements (or transactions) with same time-stamp are anticipated/handled
$ !!--   in export processing, however may have a random sorted position,
$ !!--   so for testing determinism, here a 1 sec delay is introduced to separate
$ !!--   the transactions.
$ !!--
$ !cms create elem elem*.txt "''testTag'"
$
$ cms create elem elem2.txt "''testTag'"
$ gosub GOSUB_WAIT
$ cms create elem elem3.txt "''testTag'"
$
$ cms create group CURRENT "''testTag':1"
$ cms insert elem elem*.txt CURRENT "''testTag':2"
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T10:$ testName = "manyElemsMainline"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- multiple updates to multiple elems on mainline
$
$ cms reserve CURRENT "''testTag':1"
$ pipe write sys$output "''testTag':1" | append sys$input elem1.txt
$ pipe write sys$output "''testTag':1" | append sys$input elem2.txt
$ pipe write sys$output "''testTag':1" | append sys$input elem3.txt
$ !!cms replace /if CURRENT "''testTag':1"
$
$ cms replace /if elem1.txt "''testTag':1"
$ gosub GOSUB_WAIT
$ cms replace /if elem2.txt "''testTag':1"
$ gosub GOSUB_WAIT
$ cms replace /if elem3.txt "''testTag':1"
$ gosub GOSUB_WAIT
$
$
$ cms reserve CURRENT "''testTag':2"
$ pipe write sys$output "''testTag':2" | append sys$input elem3.txt
$ cms replace /if CURRENT "''testTag':2"
$ gosub GOSUB_WAIT
$
$ cms reserve CURRENT "''testTag':3"
$ pipe write sys$output "''testTag':3" | append sys$input elem2.txt
$ cms replace /if CURRENT "''testTag':3"
$ gosub GOSUB_WAIT
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T11:$ testName = "manyVarlines"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- create and update variants of many elements
$
$ current_startGEN = "-1"
$ current_VAR = "X"
$
$ cms reserve CURRENT /GEN='current_startGEN' "''testTag':1"
$ pipe write sys$output "''testTag':1" | append sys$input elem2.txt
$ pipe write sys$output "''testTag':1" | append sys$input elem3.txt
$ !!cms replace /if CURRENT /VAR='current_VAR' "''testTag':1"
$
$ cms replace /if elem1.txt /VAR='current_VAR' "''testTag':1"
$ gosub GOSUB_WAIT
$ cms replace /if elem2.txt /VAR='current_VAR' "''testTag':1"
$ gosub GOSUB_WAIT
$ cms replace /if elem3.txt /VAR='current_VAR' "''testTag':1"
$ gosub GOSUB_WAIT
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T12:$ testName = "mergeVarline"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- merge varline into mainline
$
$ !!-- if needed, advance the mainline, so that mainline gen not on varline
$ !!--
$ current_startGEN = "1+"
$ merge_varline = "2X"
$ merge_varGen = 1
$ merge_GEN = merge_varline + f$str(merge_varGen) + "+"  !! TOADD:use class
$
$ cms reserve CURRENT /GEN='current_startGEN' /MERGE='merge_GEN' "''testTag':1"
$
$ !!-- resolve conflicts
$ !!--   for this case just keep both original and merged changes
$ !!--   so simply remove the conflict markup
$ !!--   here we know that 2X1+ has only elem2.txt and elem3.txt
$ !!--
$ pipe type elem2.txt | search sys$input  "********" /match=nor /out=elem2.txt;
$ pipe type elem3.txt | search sys$input  "********" /match=nor /out=elem3.txt;
$
$ !!cms replace /if CURRENT "''testTag':1"
$
$ cms replace /if elem2.txt "''testTag':1"
$ gosub GOSUB_WAIT
$ cms replace /if elem3.txt "''testTag':1"
$ gosub GOSUB_WAIT
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T13:$ testName = "renameElems"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- rename elements
$
$ cms modif elem elem2.txt /name=elemX.txt "''testTag':1"
$ gosub GOSUB_WAIT
$ cms modif elem elem3.txt /name=elem2.txt "''testTag':2"
$ gosub GOSUB_WAIT
$ cms modif elem elemX.txt /name=elem3.txt "''testTag':3"
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T14:$ testName = "deleteGens"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- delete existing generations
$
$ cms delete gen /noconf elem1.txt /gen=6 "''testTag':1"
$ cms delete gen /noconf elem1.txt /gen=5A2V2 "''testTag':2"
$ cms delete gen /noconf elem1.txt /gen=5A2V1 "''testTag':3"
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T15:$ testName = "binaryElem"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- create a binary element
$
$ zipFileName = "[.data]binaryelem.zip"
$ cms create elem /keep 'zipFileName' /binary "''testTag':1"
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T16:$ testName = "emptyClass"
$
$!-- NOTE:: this test breaks with CMS-4.5 (cms sh class /cont => %SYSTEM-F-ACCVIO)
$!-- so technically, any class-related tests will break
$!-- CMS must be patched to CMS-4.5-2 (DECSET128ECO1)
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- create new CMS class, leave it empty
$
$ cms create class class1 "''testTag'"
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T17:$ testName = "oneElemClass"
$
$!-- NOTE:: this test breaks with CMS-4.5 (cms sh class /cont => %SYSTEM-F-ACCVIO)
$!-- so technically, any class-related tests will break
$!-- CMS must be patched to CMS-4.5-2 (DECSET128ECO1)
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- class with a single elem generation
$
$ cms insert gen elem1.txt class1 "''testTag':1"
$ cms modify class class1 /remark="''testTag'" "''testTag':2"
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T18:$ testName = "classes"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- create classes and populate them with generations
$
$ cms create class LATEST "''testTag':1"
$ cms insert gen CURRENT LATEST "''testTag':2"
$
$ gosub GOSUB_WAIT
$ cms create class V1.0 "''testTag':3"
$ cms insert gen CURRENT /GEN=-1 V1.0 "''testTag':4"
$
$ gosub GOSUB_WAIT
$ cms create class PATCH_X "''testTag':3"
$ cms insert gen CURRENT /GEN=2X1+ PATCH_X "''testTag':5"
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T19:$ testName = "classBranchXref"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- create class-branch xref file to map classes to branches
$
$ classBranchXrefFile = "CLASSBRANCH.XREF"
$
$ create 'classBranchXrefFile'
$DECK
latest:release|
v1.0:release|
$EOD
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$ xcmsClassBranchXrefFile = classBranchXrefFile
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return


$!-------------------------------
$GOSUB_TST_T:$ testName = "NEWTEST"
$
$ testTag = test
$ if (testName .nes. "") then testTag = "''test'_''testName'"
$ logmsg "I|TESTING:", testTag
$
$ testPassed = "F"
$
$BEGIN_CMS_CHANGES:!!-- DESCRIPTION
$
$
$END_CMS_CHANGES:
$
$ gosub GOSUB_INIT_EXPORTCMS
$
$ gosub GOSUB_TEST_EXPORTCMS
$
$ return

$endsubroutine !RUN_TESTS


$!============================================================================
$USAGE_DETAILS:subroutine
$ gosub LICENSE
$
$ logmsg "I|USAGE_DETAILS:"
$
$ type sys$input
$DECK
INFO:
Test-runner for CMS-EXPORT project. Usually executed as part of build process.
Each test makes changes to a test CMS library, runs the CMS export utililty and
matches the resulting export file to expected output (in [.data] sub-dir).

DETAILS:
- Available tests are listed in DEFAULT_TEST_LIST symbol
- Disabled tests are prefixed with "-" (e.g. "-T05")
- Tests are done sequentially as listed left to right
- Each test must have a corresponding GOSUB_TST_<test> to execute
- Listed tests may be ordinary tests or test-groups
- Test group is a test sub-list
- For a test group: first all tests in the group are done,
  then the group's own test is done

RETURNS:
On successful completion of all enabled tests the $STATUS is set as:
    STS_SUCCESS = "%X10000001"

If some test failed, the returned $STATUS may be retained from the failed command.
However, it is intended to continue to the next test even after a failing one.
On completion with any test having failed, the $STATUS is set as:
    STS_ERROR = "%X10000002"

The resulting export files are named per test's tag, the matching differences
file is named after the test and has a suffix PASSED/FAILED appended (e.g.
T06.DIF_PASSED)

EXAMPLES:
    $ @testxcms
    $ dir *.*FAILED

$EOD
$
$ exit !USAGE_DETAILS

$LICENSE:
$ logmsg "I|LICENSE:"
$
$ type sys$input
$DECK
-----------------------------------------------------------------------------
Copyright (c) 2015, Artur Shepilko, <cms-export@nomadbyte.com>.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
-----------------------------------------------------------------------------
$EOD
$
$ return !LICENSE

$endsubroutine !USAGE_DETAILS
