$!===========================================================================
$ THIS_FILE = f$elem(0,";",f$env("procedure"))
$ USAGE_ARGS = "[target1[ target2 ...]]"
$ PRJ_NAME = "XCMS"
$ THIS_FACILITY = "BUILD''PRJ_NAME'"
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
$ DEFAULT_TARGET_LIST = "clean all test"
$ TARGET_LIST_all = "main"
$
$ sts = STS_ERROR
$
$GET_ARGS:
$ if (f$extr(0,1,p1) .eqs. "?") then goto USAGE
$
$ targetList = f$edit("''p1' ''p2' ''p3' ''p4' ''p5' ''p6'","TRIM,LOWERCASE")
$ if (targetList .eqs. "") then targetList = DEFAULT_TARGET_LIST
$
$ sourceDir = f$parse(f$env("PROCEDURE"),,,"DEVICE") -
              + f$parse(f$env("PROCEDURE"),,,"DIRECTORY")
$ buildDir = f$edit(f$trnlnm("BUILD_DIR"), "UPCASE")
$ if (buildDir .eqs. "") then buildDir = f$env("DEFAULT")
$
$ if (buildDir .eqs. sourceDir) then goto E_INSOURCE
$
$!----------------------------------
$ CHAR_SPACE = " " !!space
$
$ call PROCESS_TARGETS "''targetList'"
$
$
$ sts = STS_SUCCESS
$
$EXIT:
$ set def 'defaultDir'
$ exit 'sts' + (0 * f$verify(saveVerify))

$USAGE:
$ logmsg "I|COPYRIGHT:", COPYRIGHT
$ logmsg "I|VERSION:", VERSION
$ logmsg "I|USAGE:", USAGE
$ logmsg "I|DEFAULT_TARGET_LIST:", DEFAULT_TARGET_LIST
$
$ logmsg "I|HELP:Run with ?? for usage details and license."
$ if (f$extr(0,2,p1) .eqs. "??") then call USAGE_DETAILS
$ goto EXIT

$ERROR:
$ errmsg "E|FAILED"
$ set def 'defaultDir'
$ exit 'sts' + (0 * f$verify(saveVerify))

$E_INSOURCE:
$ errmsg "E|INSOURCE, only out-of-source build supported; run from a build dir"
$ goto ERROR

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
$SETUP: subroutine
$
$EXIT:
$ exit !SETUP
$endsubroutine !SETUP


$!============================================================================
$PROCESS_TARGETS: subroutine
$
$ groupTargetList = f$edit(p1,"TRIM,COMPRESS")
$
$ gosub GOSUB_SETUP
$
$ gtid = 0
$DO_GROUP:
$   groupTarget = f$elem(gtid,CHAR_SPACE, groupTargetList)
$   if (groupTarget .eqs. CHAR_SPACE) then goto ENDDO_GROUP
$   if (groupTarget .eqs. "") then goto NEXT_GROUP
$
$   targetList = ""
$   if (f$type(TARGET_LIST_'groupTarget') .nes. "") -
      then targetList = f$edit(TARGET_LIST_'groupTarget',"COMPRESS")
$
$   if (targetList .eqs. "") then targetList = groupTarget
$
$   tid = 0
$DO_TARGET:
$   target = f$elem(tid,CHAR_SPACE, targetList)
$   if (target .eqs. CHAR_SPACE) then target = groupTarget
$   if (target .eqs. "") then goto NEXT_TARGET
$
$   logmsg "I|TARGET:", target
$   gosub GOSUB_DO_'target'
$
$NEXT_TARGET:
$   if (target .eqs. groupTarget) then goto ENDDO_TARGET
$   tid = tid + 1
$   goto DO_TARGET
$ENDDO_TARGET:
$
$NEXT_GROUP:
$   gtid = gtid + 1
$   goto DO_GROUP
$ENDDO_GROUP:
$
$EXIT:
$ gosub GOSUB_TEARDOWN
$ exit !PROCESS_TARGETS
$
$ERROR:
$ goto EXIT

$!----------------------------------------
$GOSUB_SETUP:
$ logmsg "I|SETUP"
$
$ !!-- define logicals for source and build roots
$ !!--
$ dir = sourceDir
$ dev = f$parse(dir,,,"DEVICE")
$ devDir = f$trnlnm(dev - ":")
$ if (devDir .nes. "") then dev = devDir
$
$ prjRoot = dev + f$parse(dir,,,"DIRECTORY") - "][" - "]" + ".]"
$
$ dir = buildDir
$ dev = f$parse(dir,,,"DEVICE")
$ devDir = f$trnlnm(dev - ":")
$ if (devDir .nes. "") then dev = devDir
$
$ bldRoot = dev + f$parse(dir,,,"DIRECTORY") - "][" - "]" + ".]"
$
$ define /nolog PRJROOT 'prjRoot /trans=conceal
$ define /nolog BLDROOT 'bldRoot /trans=conceal
$
$ logmsg "I|PRJROOT=" , f$trnlnm("PRJROOT")
$ logmsg "I|BLDROOT=" , f$trnlnm("BLDROOT")
$ return

$!----------------------------------------
$GOSUB_TEARDOWN:
$ logmsg "I|TEARDOWN"
$
$ return

$!----------------------------------------
$GOSUB_DO_all:
$ logmsg "I|STARTING:",target
$
$ return

$!----------------------------------------
$GOSUB_DO_main:
$ logmsg "I|STARTING:",target
$
$ if (f$parse("BLDROOT:[src]") .eqs. "") then create /dir BLDROOT:[src]
$ if (f$parse("BLDROOT:[bin]") .eqs. "") then create /dir BLDROOT:[bin]
$
$ set def BLDROOT:[src]
$
$ copy /log PRJROOT:[src]*.com BLDROOT:[bin]
$
$ return

$!----------------------------------------
$GOSUB_DO_test:
$ logmsg "I|STARTING:",target
$
$ if (f$parse("BLDROOT:[tests]") .eqs. "") then create /dir BLDROOT:[tests]
$ set def BLDROOT:[tests]
$
$ copy /log PRJROOT:[tests]*.com []
$
$ create /dir [.data]
$ copy /log PRJROOT:[tests.data]*.* [.data]
$
$ @testxcms
$
$ return

$!----------------------------------------
$GOSUB_DO_clean:
$ logmsg "I|STARTING:",target
$
$ if (f$trnlnm("BLDROOT") .eqs. f$trnlnm("PRJROOT") -
      .or. f$parse("BLDROOT:[000000]") .eqs. "" -
      .or. f$search("BLDROOT:[000000]*.*") .eqs. "") then return
$
$ set def BLDROOT:[000000]
$
$ set file /by /prot=o:rwed []*.*,[...]*.*
$ pipe deletex /noconf /by [...]*.*;*,;,;,;,;,;,;,;,[]*.*;* >NL: 2>NL:
$
$ return

$endsubroutine !PROCESS_TARGETS


$!============================================================================
$USAGE_DETAILS:subroutine
$ gosub LICENSE
$
$ logmsg "I|USAGE_DETAILS:"
$
$ type sys$input
$DECK
INFO:
Build utility for CMS-EXPORT project.

DETAILS:
- Supports building of a single target or a target list (space-separated)
- Targets are made in the listed order left-to-right
- Each target must have a corresponding GOSUB_DO_<target> to execute
- Listed targets may be ordinary targets or target-groups
- Target group is a target sub-list
- For a target group: first all targets in the group are made,
  then the group's own target is made

RETURNS:
On successful completion of the requested targets $STATUS is set as:
    STS_SUCCESS = "%X10000001"

If target build failed, the returned $STATUS may be retained from the
failed command, otherwise it is set as:
    STS_ERROR = "%X10000002"

EXAMPLES:
    $ @build clean all test

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

$endsubroutine