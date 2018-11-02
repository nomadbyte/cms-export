$!===========================================================================
$ THIS_FILE = f$elem(0,";",f$env("procedure"))
$ USAGE_ARGS = "[libPath] [outFile] [elemList] [classList] [classBranchXref]"
$ THIS_FACILITY = "EXPORTCMS"
$ VERSION = "0.11.0"
$ COPYRIGHT = "Copyright (c) 2018, Artur Shepilko, <cms-export@nomadbyte.com>."
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
$!
$ dbgmsg "DBG|FILE:", THIS_FILE
$!
$ STS_SUCCESS = "%X10000001"
$ STS_ERROR = "%X10000002"
$
$!-----------------------------
$ DEFAULT_CMSLIB_PATH = "CMS$LIB:"
$ DEFAULT_EXP_FILE = "CMSLIB.GIT-FAST"
$ DEFAULT_ELEM_LIST = "*.*"
$ DEFAULT_CLASS_LIST = "*"
$
$ libPath = ""
$ libName = ""
$ expFile = ""
$ elemList = ""
$ classList = ""
$ xrefClassBranchFile = ""
$
$ if (f$extr(0,1,p1) .eqs. "?") then goto USAGE
$
$ gosub GOSUB_GET_ARGS
$
$ if (libPath .eqs. "") then goto ERROR
$
$ dbgmsg "DBG|libName:", libName
$!-----------------------------
$!
$ CHAR_SPACE = " "
$ CHAR_PIPE = "|"
$ CHAR_DBLQUOTE = """"
$!
$ STS_CMS_LIBSET = "%X109C8421"
$
$ set noon
$ cms set lib 'libPath'
$ stsCMS = $STATUS
$ set on
$ if (stsCMS .nes. STS_CMS_LIBSET) then goto ERROR
$!
$!
$ histCommitsFile = "CMSLIB.COMMITS"
$ call CREATE_HISTCOMMITS_FILE "''histCommitsFile'" "''elemList'"
$!
$ classesFile = "CMSLIB.CLASSES"
$ call CREATE_CLASSES_FILE "''classesFile'" "''histCommitsFile'" "''classList'" -
       "''xrefClassBranchFile'"
$
$ call EXPORT_GIT "''histCommitsFile'" "''classesFile'" "''expFile'" "" 'g_histLastCommitId
$
$ sts = STS_SUCCESS
$!
$EXIT:
$ exit 'sts' + (0 * f$verify(saveVerify))

$ERROR:
$ sts = STS_ERROR
$ errmsg "E|ERROR"
$ goto EXIT

$USAGE:
$ sts = STS_ERROR
$ logmsg "I|COPYRIGHT:", COPYRIGHT
$ logmsg "I|VERSION:", VERSION
$ logmsg "I|USAGE:", USAGE
$
$ logmsg "I|HELP:Run with ?? for usage details and license."
$ if (f$extr(0,2,p1) .eqs. "??") then call USAGE_DETAILS
$ goto EXIT


$!-------------------------------
$GOSUB_GET_ARGS:
$ dbgtrace "GOSUB_GET_ARGS"
$
$ libPath = p1
$
$ if (libPath .eqs. "") then libPath = DEFAULT_CMSLIB_PATH
$ libPath = f$parse(libPath,,,,"SYNTAX_ONLY") - ".;"
$ if (libPath .eqs. "" -
      .or. f$parse(libPath,,,"NAME") .nes. "")
$ then
$   libPath = ""
$   goto EXIT_GET_ARGS
$ endif
$
$ !!-- Get CMS lib name from path (DEV:[LIBNAME] or DEV:[DIR.LIBNAME])
$ !!-- OR get it from device name when a terminal device (DEV: or DEV:[000000])
$ !!--
$ if (libPath - "]" .eqs. libPath -
      .or. libPath - "[000000]" .nes. libPath)
$ then
$   libDirName = f$edit(libPath, "LOWERCASE") - "[000000]" - ":"
$ else
$   libDirName = f$edit(libPath, "LOWERCASE") - "]" -
         - f$edit(f$parse(libPath - "]" + ".-]",,,,"SYNTAX_ONLY") -
           - "000000].;" - "].;", "LOWERCASE") - "000000." - "."
$ endif
$!
$ expFile = p2
$ if (expFile .eqs. "" -
      .or. f$parse(expFile,,,"TYPE") .eqs. ".") then -
    expFile = f$parse(libName, DEFAULT_EXP_FILE) - ";"
$!
$ elemList = p3
$ if (elemList .eqs. "") then elemList = DEFAULT_ELEM_LIST
$!
$ classList = p4
$ if (classList .eqs. "") then classList = DEFAULT_CLASS_LIST
$!
$ xrefClassBranchFile = p5
$
$
$EXIT_GET_ARGS:
$ return  !GOSUB_GET_ARGS


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



$!===========================================================================
$CREATE_HISTCOMMITS_FILE:subroutine
$ dbgtrace "CREATE_HISTCOMMITS_FILE"
$
$ sts = STS_ERROR
$
$ !!-- init retvals
$ g_histLastCommitId == 0
$ g_histLastBlobId == 0
$
$ outFile = p1
$ elemList = p2
$!
$ if (outFile .eqs. "") then goto EXIT
$
$ type /nohead NL: /out='outFile'
$
$ initCommitId = 1
$ commitId = initCommitId !! odd
$ blobId = commitId + 1   !! even
$ idStep = 2
$
$ !!-- write lib info in first commits record
$ !!--
$ call GET_LIBHIST_INFO
$
$ initCommitsRec = g_libSeqKey -
          +CHAR_PIPE+ g_lib -
          +CHAR_PIPE+ ":" -
          +CHAR_PIPE+ f$str(initCommitId) -
          +CHAR_PIPE+ f$str(0) -
          +CHAR_PIPE+ f$str(0) -
          +CHAR_PIPE+ g_libTime -
          +CHAR_PIPE+ g_libUser -
          +CHAR_PIPE+ CHAR_DBLQUOTE+ g_libRemark +CHAR_DBLQUOTE
$!
$ dbgmsg "DBG|initCommitsRec:",initCommitsRec
$
$ pipe write sys$output initCommitsRec | append sys$input 'outFile'
$
$
$ !!-- process element generations
$ !!--
$ genHistFile = "CMSLIB.TMP_GENHIST"
$ call CREATE_GENHIST_FILE "''genHistFile'"  "''elemList'"
$!
$ open /read fGenHist 'genHistFile'
$
$ cachedElem = ""
$ cachedGen = ""
$ cachedCommitId = 0
$!
$DO_GENHIST:
$   line = ""
$   read/end=ENDDO_GENHIST fGenHist line
$   if (line .eqs. "") then goto NEXT_GENHIST
$!
$   call PARSE_HISTCOMMITS_REC
$   curSeqKey = g_histSeqKey
$
$   call GET_CURGEN_ANC "''g_histElem'" "''g_histGen'" 1
$
$   if (g_ancGen .eqs. "")
$   then
$     ancCommitId = commitId
$   else
$     if (g_ancElem .eqs. cachedElem -
          .and. g_ancGen .eqs. cachedGen)
$     then
$       ancCommitId = cachedCommitId
$     else
$       call GET_HISTCOMMITS  "''outFile'" "" "''g_ancElem'" "''g_ancGen'"
$       ancCommitId = g_histCommitId
$     endif
$   endif
$
$   commitId = commitId + idStep
$   blobId = blobId + idStep
$!
$   curCommitsRec = curSeqKey -
          +CHAR_PIPE+ g_curElem -
          +CHAR_PIPE+ "''g_curGen':''g_ancGen'" -
          +CHAR_PIPE+ f$str(commitId) -
          +CHAR_PIPE+ f$str(ancCommitId) -
          +CHAR_PIPE+ f$str(blobId) -
          +CHAR_PIPE+ g_curTime -
          +CHAR_PIPE+ g_curUser -
          +CHAR_PIPE+ CHAR_DBLQUOTE+ g_curRemark +CHAR_DBLQUOTE
$!
$   dbgmsg "DBG|curCommitsRec:",curCommitsRec
$
$   pipe write sys$output curCommitsRec | append sys$input 'outFile'
$!
$NEXT_GENHIST:
$   cachedElem = g_curElem
$   cachedGen = g_curGen
$   cachedCommitId = commitId
$   goto DO_GENHIST
$!
$ENDDO_GENHIST:
$ if (f$trnlnm("fGenHist") .nes. "") then close fGenHist
$ if (f$search(genHistFile) .nes. "") then del /nolog/noconf 'genHistFile';*
$!
$ g_histLastCommitId == commitId
$ g_histLastBlobId == blobId
$
$ sts = STS_SUCCESS
$!
$EXIT:
$ exit 'sts' !CREATE_HISTCOMMITS_FILE
$endsubroutine


$!===========================================================================
$CREATE_CLASSES_FILE:subroutine
$ dbgtrace "CREATE_CLASSES_FILE"
$
$ sts = STS_ERROR
$
$ outFile = p1
$ histCommitsFile = p2
$ classList = p3
$ xrefClassBranchFile = p4
$
$ !!-- init retvals
$
$ if (outFile .eqs. "") then goto EXIT
$
$ type /nohead NL: /out='outFile'
$
$ !!-- process class contents
$ !!--
$ classHistFile = "CMSLIB.TMP_CLASSHIST"
$ call CREATE_CLASSHIST_FILE "''classHistFile'" "''histCommitsFile'" "''classList'"
$
$ open /read fClassHist 'classHistFile'
$
$ classSeqKey = ""
$ classBranch = ""
$!
$DO_CLASSHIST:
$   line = ""
$   read/end=ENDDO_CLASSHIST fClassHist line
$   if (line .eqs. "") then goto NEXT_CLASSHIST
$!
$   call PARSE_CLASSHIST_REC
$
$   !!-- propagate class' histSeqKey to all its member gens
$   !!-- also xref class to branch
$   !!--
$   if (g_classIsName)
$   then
$     classSeqKey = g_classHistSeqKey
$     classBranch = ""
$
$     if (xrefClassBranchFile .nes. "")
$     then
$       call GET_XREF_CLASSBRANCH "''xrefClassBranchFile'" "''g_class'"
$       classBranch = g_xrefClassBranch
$     endif
$
$     if (classBranch .eqs. "") then classBranch = g_class
$   endif
$
$   g_classBranch == classBranch
$   g_classSeqKey == classSeqKey
$
$   classHistRec = CHAR_PIPE+ g_classBranch -
                 +CHAR_PIPE+ g_classSeqKey -
                 +CHAR_PIPE+ g_class -
                 +CHAR_PIPE+ f$str(g_classBlobId) -
                 +CHAR_PIPE+ g_classHistSeqKey -
                 +CHAR_PIPE+ g_classElem -
                 +CHAR_PIPE+ g_classGen -
                 +CHAR_PIPE+ g_classTime -
                 +CHAR_PIPE+ g_classUser -
                 +CHAR_PIPE+ CHAR_DBLQUOTE+ g_classRemark +CHAR_DBLQUOTE
$!
$   dbgmsg "DBG|classHistRec:",classHistRec
$
$   pipe write sys$output classHistRec | append sys$input 'outFile'
$
$
$NEXT_CLASSHIST:
$   goto DO_CLASSHIST
$ENDDO_CLASSHIST:
$ if (f$trnlnm("fClassHist") .nes. "") then close fClassHist
$ if (f$search(classHistFile) .nes. "") then del /nolog/noconf 'classHistFile';*
$
$ !!-- sort ascending by branch+seqkey+class+blobid
$ sort 'outFile' 'outFile';
$
$ sts = STS_SUCCESS
$!
$EXIT:
$ exit 'sts' !CREATE_CLASSES_FILE
$endsubroutine



$!===========================================================================
$EXPORT_GIT:subroutine
$ dbgtrace "EXPORT_GIT"
$
$ sts = STS_ERROR
$
$ DEFAULT_MAINLINE = "master"
$!
$ histCommitsFile = p1
$ classesFile = p2
$ outFile = p3
$ mainlineBranch = p4
$ lastCommitId = f$int(p5)
$
$ if (histCommitsFile .eqs. "") then goto EXIT
$ if (outFile .eqs. "") then goto EXIT
$ if (mainlineBranch .eqs. "") then mainlineBranch=DEFAULT_MAINLINE
$
$ !!-- create output file as STREAM_LF
$ !!--
$ fdlFile = outFile - f$parse(outFile,,,"VERSION") + "_FDL"
$ type /nohead NL: /out='fdlFile'
$ set file 'fdlFile' /attr=(RFM:STMLF, RAT:CR, LRL:32767, MRS:0)
$ analyze /rms /fdl 'fdlFile' /out='fdlFile';
$
$ create /fdl='fdlFile' 'outFile'
$ del /nolog /noconf 'fdlFile';*
$
$ open /append fExportOut 'outFile'
$!
$ !!-- process all histCommits, generate git-blobs and git-commit records
$ !!--
$ open /read fHistCommits 'histCommitsFile'
$
$ idStep = 2
$ commitId = lastCommitId + idStep
$ libName = ""
$
$DO_HISTCOMMITS:
$   line = ""
$   read /end=ENDDO_HISTCOMMITS  fHistCommits line
$
$   call PARSE_HISTCOMMITS_REC
$
$   curHistSeqKey = g_histSeqKey
$   curHistElem = g_histElem
$   curHistGen = g_histGen
$   curHistAncGen = g_histAncGen
$   curHistCommitId = g_histCommitId
$   curHistAncId = g_histAncId
$   curHistBlobId = g_histBlobId
$   curHistTime = g_histTime
$   curHistUser = g_histUser
$   curHistRemark = g_histRemark
$
$   !!-- process inital commit to get lib-info
$   !!--
$   if (libName .eqs. "")
$   then
$     if (curHistCommitId .ne. 0 -
           .and. curHistAncId .eq. 0)
$     then
$       libName = curHistElem
$       initCommitId = curHistCommitId
$     else
$       goto ENDDO_HISTCOMMITS
$     endif
$   endif
$
$   !!-- export blobs
$   !!--
$   if (curHistBlobId .ne. 0)
$   then
$     blobFile = "''libName'.BLOB_''curHistBlobId'"
$!
$     call CREATE_GENBLOB_FILE "''curHistElem'" "''curHistGen'" "''blobFile'"
$
$     histBlobId = curHistBlobId
$     gosub GOSUB_WRITE_GIT_BLOB
$
$     if (f$search(blobFile) .nes. "") then del /nolog /noconf 'blobFile';*
$   endif
$
$   !!-- export commits
$   !!-- commit mainline generations to default trunk branch
$   !!-- commit variants into variant branches per generation-variant
$   !!-- variant branches are standalone, to isolate the variant changes
$   !!-- variant branch starts from individual commit of variant's ancestor
$   !!-- e.g.  file.c (1A1:1) - gen-variant:1A, branch: var-(file.c;1A)
$   !!--       file.c (3A2T1:3A2) - gen-variant:3A2T, branch: var-(file.c;3A2T)
$   !!--       file.c (3A15:3A2) - not variant! - same branch: var-(file.c;3A)
$
$   isMainlineCommit = (f$int(curHistGen) .gt. 0 -
                        .or. curHistCommitId .eqs. initCommitId)
$   branch = mainlineBranch
$
$   !!-- detect variant-branching
$   !!-
$   isNewVarline = "F"
$   isNewVarlineBranch = "F"
$   if (.not. isMainlineCommit)
$   then
$     var = ""
$!
$     genDif = curHistGen - curHistAncGen
$     if (genDif .nes. curHistGen)
$     then
$       !!-- var must be [A-Z,_]
$       !!-- NOTE: f$int("T")= f$int("TRUE")= 1)
$       !!-- NOTE2: handle long variant names (up to 255 char)
$       !!-- loop until first digit or end
$!
$       len = f$len(genDif)
$       idx = 0
$DO_VAR:
$       if (f$extr(idx, 1, genDif) .nes. "T" -
            .and. f$int(f$extr(idx, 1, genDif)) .ne. 0) then goto ENDDO_VAR
$       idx = idx + 1
$       if (idx .ge. len)  !!-- varN
$       then
$         !!-- ERROR: invalid variant generation
$         goto EXIT
$       endif
$       goto DO_VAR
$ENDDO_VAR:
$
$       var = f$edit(f$extr(0,idx,genDif) , "UPCASE")
$     endif
$
$     if (var .nes. "")
$     then
$       !!-- must be direct ancestor var
$       varline = curHistAncGen + var
$       if (f$int(curHistGen - varline) .eq. 0) !!-- 3G2F5T1 <- 3G2 (vs. 3G2F5)
$       then
$         !!-- ERROR:invalid commit
$         var = ""
$         varline = ""
$         goto EXIT
$       endif
$
$     else
$       !!-- non-branching varline commit
$       !!-- e.g. 3F4G5 <- 3F4G2 (varline: 3F4G, init: 3F4)
$       !!-- to determine the varline:
$       !!--   chop from gen end, until f$int(chunk)=0
$       !!--   e.g. 3F4T123 >> 3F4[T123] >> 3F4T + 123
$       gen = curHistGen
$       len = f$len(gen)
$       idx = len - 2    !!-- len(variant) >= 3
$DO_VARLINE:
$       if (f$int(f$extr(idx, len - idx, gen)) .eq. 0 -
            .or. f$extr(idx, 1, gen) .eqs. "T" ) then goto ENDDO_VARLINE
$       idx = idx - 1
$       if (idx .le. 0)
$       then
$         !!-- ERROR: invalid variant generation
$         goto EXIT
$       endif
$       goto DO_VARLINE
$ENDDO_VARLINE:
$
$       varline = f$extr(0, idx + 1, gen)
$     endif
$!
$     isNewVarline = (var .nes. "")
$     isNewVarlineBranch = (isNewVarline .and. f$int(curHistAncGen) .eq. 0)
$!
$     varline = f$edit(varline,"LOWERCASE")
$     branch = "var-(''curHistElem';''varline')"
$
$   endif
$
$
$   commitHead = "refs/heads/''branch'"
$!
$   !!-- initiate a new branch for the new varline
$   !!--   initial commit is the ancestor of the variant gen
$   if (isNewVarline .and. -
        .not. isNewVarlineBranch)
$   then
$     call GET_HISTCOMMITS  "''histCommitsFile'" "" "''curHistElem'" "''curHistAncGen'"
$
$     ancHistSeqKey = g_histSeqKey
$     ancHistElem = g_histElem
$     ancHistGen = g_histGen
$     ancHistAncGen = g_histAncGen
$     ancHistCommitId = g_histCommitId
$     ancHistAncId = g_histAncId
$     ancHistBlobId = g_histBlobId
$     ancHistTime = g_histTime
$     ancHistUser = g_histUser
$     ancHistRemark = g_histRemark
$!
$     commitId = commitId + idStep
$     branchInitCommitId =  commitId
$
$     !!-- setup params for git commit entry
$     !!--
$     histCommitId = branchInitCommitId
$     commitTime = ancHistTime
$     commitUser = ancHistUser
$     commitRemark = "(''ancHistElem';''ancHistGen'):" + ancHistRemark
$
$     commitFromId = initCommitId  !!-- new variline starts from root
$!
$     commitCommand = "M 100644 :''ancHistBlobId' ''ancHistElem'"
$
$     gosub GOSUB_WRITE_GIT_COMMIT
$   endif
$!
$
$   !!-- setup params for git commit entry
$   !!--
$   histCommitId = curHistCommitId
$   commitTime = curHistTime
$   commitUser = curHistUser
$!
$   if (curHistCommitId .eqs. initCommitId)
$   then
$     commitRemark = "initial empty check-in"
$     commitFromId = 0  !!-- no ancestor commit for root
$     commitCommand = "deleteall"
$!
$   else
$     commitRemark = "(''curHistElem';''curHistGen'):" + curHistRemark
$!
$     commitFromId = curHistAncId
$     if (isMainlineCommit) then commitFromId = prevMainlineCommitId
$     if (isNewVarline .and. -
          .not. isNewVarlineBranch) then commitFromId = branchInitCommitId
$
$     commitCommand = "M 100644 :''curHistBlobId' ''curHistElem'"
$   endif
$!
$   gosub GOSUB_WRITE_GIT_COMMIT
$!
$!
$NEXT_HISTCOMMITS:
$   if (isMainlineCommit) then prevMainlineCommitId = curHistCommitId
$   goto DO_HISTCOMMITS
$ENDDO_HISTCOMMITS:
$ if (f$trnlnm("fHistCommits") .nes. "") then close fHistCommits
$
$
$ !!-- process classes
$ !!--
$ open /read fClasses 'classesFile'
$
$ class = ""
$ prevClassBranch = ""
$ prevClassSeqKey = ""
$ prevClassCommitId = 0
$ isTaggedCommit = ""
$
$DO_CLASSES:
$   line = ""
$   read /end=ENDDO_CLASSES  fClasses line
$
$   call PARSE_CLASSHIST_REC
$
$   if (g_classIsName)
$   then
$     !!-- close the previous class commit record
$     !!-- generate tag for classes committed to same branch
$     !!--
$     if (class .nes. "")
$     then
$       write fExportOut ""
$
$       if (isTaggedCommit)
$       then
$         commitTag = class
$         tagCommitFromId = commitId
$         tagUser = commitUser
$         tagTime = commitTime
$
$         gosub GOSUB_WRITE_GIT_TAG
$       endif
$     endif
$
$     !!-- open current class
$     !!--
$     class = g_class
$     classSeqKey = g_classSeqKey
$
$     branch = g_classBranch
$     if (branch .eqs. "") then branch = class
$
$     isTaggedCommit = (branch .nes. class)
$
$     commitHead = "refs/heads/''branch'"
$
$     commitId = commitId + idStep
$
$     histCommitId = commitId
$     commitTime = g_classTime
$     commitUser = g_classUser
$     commitRemark = g_classRemark
$     commitCommand = ""
$
$     commitFromId = initCommitId
$
$     isBranchHistCommit = (branch .nes. "" -
                        .and. branch .eqs. prevClassBranch -
                        .and. classSeqKey .ges. prevClassSeqKey)
$
$     if (isBranchHistCommit)
$     then
$       commitFromId = prevClassCommitId
$     endif
$
$     prevClassBranch = branch
$     prevClassSeqKey = classSeqKey
$     prevClassCommitId = commitId
$
$     gosub GOSUB_WRITE_GIT_COMMIT
$
$     goto NEXT_CLASSES
$   endif
$
$   commitCommand = "M 100644 :''g_classBlobId' ''g_classElem'"
$   write fExportOut commitCommand
$
$NEXT_CLASSES:
$   goto DO_CLASSES
$ENDDO_CLASSES:
$
$ if (class .nes. "")
$ then
$   write fExportOut ""
$
$   !!-- generate tag for classes committed to same branch
$   !!--
$   if (isTaggedCommit)
$   then
$     commitTag = class
$     tagCommitFromId = commitId
$     tagUser = commitUser
$     tagTime = commitTime
$
$     gosub GOSUB_WRITE_GIT_TAG
$   endif
$ endif
$
$ if (f$trnlnm("fClasses") .nes. "") then close fClasses
$
$ if (f$trnlnm("fExportOut") .nes. "") then close fExportOut
$
$ sts = STS_SUCCESS
$
$EXIT:
$ exit 'sts' !EXPORT_GIT

$!-------------------------------
$GOSUB_WRITE_GIT_COMMIT:
$ dbgtrace "GOSUB_WRITE_GIT_COMMIT"
$ !!ARGS: histCommitId,
$ !!      commitHead, commitTime, commitUser,
$ !!      commitRemark, commitFromId, commitCommand
$!
$
$ call GET_TOTSECS_TIME  "''commitTime'"
$
$ gitCommitTime = f$str(g_totSecsTime)
$ gitCommitTZOff = "+0000"
$ gitCommitterEmail = f$edit(commitUser,"LOWERCASE")
$
$ !!-- git-fast commit entry
$ !!--
$ write fExportOut "commit ", commitHead
$ write fExportOut "mark :", histCommitId
$ write fExportOut "committer ", commitUser, -
               " <",gitCommitterEmail,">", -
               " ",gitCommitTime," ", gitCommitTZOff
$!
$ write fExportOut "data ", f$len(commitRemark)
$ write fExportOut commitRemark
$!
$ if (commitFromId .gt. 0) then  write fExportOut "from :", commitFromId
$ if (commitCommand .nes. "")
$ then
$   write fExportOut commitCommand
$   write fExportOut ""
$ endif
$!
$ return  !GOSUB_WRITE_GIT_COMMIT


$!-------------------------------
$GOSUB_WRITE_GIT_TAG:
$ dbgtrace "GOSUB_WRITE_GIT_TAG"
$!! ARGS: commitTag,
$!!       tagCommitFromId, tagTime, tagUser
$
$ gitTagRemark = ""   !! No remark, needs to be UTF-8 encoded
$
$ call GET_TOTSECS_TIME  "''tagTime'"
$
$ gitTagTime = f$str(g_totSecsTime)
$ gitTagTZOff = "+0000"
$ gitTaggerEmail = f$edit(tagUser,"LOWERCASE")
$
$ !!-- git-fast tag
$ !!--
$ write fExportOut "tag ", commitTag
$ write fExportOut "from :", tagCommitFromId
$ write fExportOut "tagger ", tagUser, -
               " <",gitTaggerEmail,">", -
               " ",gitTagTime," ", gitTagTZOff
$
$ write fExportOut "data ", f$len(gitTagRemark)
$ if (gitTagRemark .nes. "") then write fExport gitTagRemark
$ write fExportOut ""
$
$ return  !GOSUB_WRITE_GIT_TAG


$!-------------------------------
$GOSUB_WRITE_GIT_BLOB:
$ dbgtrace "GOSUB_WRITE_GIT_BLOB"
$!! ARGS: curHistElem,
$!!       curHistGen,
$!!       histBlobId,
$!!       blobFile
$!
$
$ blockSize = f$file(blobFile,"BLS")
$ firstFreeByte = f$file(blobFile,"FFB")
$
$ gitBlobDataSize = f$file(blobFile, "EOF") * blockSize
$ if (firstFreeByte .gt. 0) then -
    gitBlobDataSize = gitBlobDataSize - blockSize + firstFreeByte
$
$ if (gitBlobDataSize .eq. 0) then -
    logmsg "W|EMPTYFILE: exporting a zero-size generation ",-
        curHistElem," /GEN=", curHistGen
$!
$ !!-- git-fast blob
$ !!--
$ write fExportOut "blob"
$ write fExportOut "mark :", histBlobId
$ write fExportOut "data ", gitBlobDataSize
$!
$ append 'blobFile' fExportOut
$ write fExportOut ""
$
$ return  !GOSUB_WRITE_GIT_BLOB

$endsubroutine !EXPORT_GIT



$!===========================================================================
$CREATE_GENBLOB_FILE:subroutine
$ dbgtrace "CREATE_GENBLOB_FILE"
$
$ elem = p1
$ gen = p2
$ outFile = p3
$!
$ if (outFile .eqs. "") then outFile = "''elem'_''gen'_BLOB"
$
$ !!-- create blob file as STREAM_LF
$ !!--
$ fdlFile = outFile - f$parse(outFile,,,"VERSION") + "_FDL"
$ type /nohead NL: /out='fdlFile'
$ set file 'fdlFile' /attr=(RFM:STMLF, RAT:CR, LRL:32767, MRS:0)
$ analyze /rms /fdl 'fdlFile' /out='fdlFile';
$
$ cms fetch 'elem' /gen='gen' /out='outFile' ""
$
$ convert /fdl='fdlFile' 'outFile' 'outFile';
$ purge /nolog /noconf 'outFile'
$ del /nolog /noconf 'fdlFile';*
$
$!
$EXIT:
$ exit !CREATE_GENBLOB_FILE
$endsubroutine


$!===========================================================================
$GET_LIBHIST_INFO:subroutine
$ dbgtrace "GET_LIBHIST_INFO"
$
$ !!-- init revals
$ !!--
$ g_lib == ""
$ g_libPath == ""
$ g_libTime == ""
$ g_libUser == ""
$ g_libRemark == ""
$ g_libSeqKey == ""
$
$ libHistFile = "CMSLIB.TMP_LIBHIST"
$!
$ cms show hist /trans=(create, modify, delete) /out='libHistFile'
$
$ open /read fLibHist 'libHistFile'
$!
$ line = ""
$SKIP_HEAD_LIBHIST:
$ read /end=ENDDO_LIBHIST fLibHist line
$ read /end=ENDDO_LIBHIST fLibHist line
$ read /end=ENDDO_LIBHIST fLibHist line
$!
$DO_LIBHIST:
$ line = ""
$ read /end=ENDDO_LIBHIST fLibHist line
$
$ call PARSE_LIBHIST_REC
$!
$ !!-- first lib hist record must be CREATE LIBRARY
$ !!--
$
$ g_libTime == g_libhistTime
$ g_libUser == g_libhistUser
$ g_libRemark == f$elem(1,CHAR_DBLQUOTE, g_libhistCommand)
$
$ g_libPath == f$edit(f$elem(0,CHAR_DBLQUOTE,g_libhistCommand),"TRIM,UPCASE") -
            - "CREATE LIBRARY "
$!
$ !!-- Get CMS lib name from path (DEV:[LIBNAME] or DEV:[DIR.LIBNAME])
$ !!-- OR get it from device name when a terminal device (DEV: or DEV:[000000])
$ !!--
$ if (g_libPath - "]" .eqs. g_libPath -
      .or. g_libPath - "[000000]" .nes. g_libPath)
$ then
$   libDirName = f$edit(g_libPath, "LOWERCASE") - "[000000]" - ":"
$ else
$   libDirName = f$edit(g_libPath, "LOWERCASE") - "]" -
         - f$edit(f$parse(g_libPath - "]" + ".-]",,,,"SYNTAX_ONLY") -
           - "000000].;" - "].;", "LOWERCASE") - "000000." - "."
$ endif
$
$ g_lib == f$edit(libDirName,"TRIM")
$ if (g_lib .eqs. "") then g_lib == "cmslib" !!-- DEFAULT
$
$ call GET_SEQTIME "''g_libTime'"
$ g_libSeqKey == g_seqTime
$
$ goto ENDDO_LIBHIST
$
$NEXT_LIBHIST:
$   goto DO_LIBHIST
$ENDDO_LIBHIST:
$ if (f$trnlnm("fLibHist") .nes. "") then close fLibHist
$ if (f$search(libHistFile) .nes. "") then del /nolog /noconf 'libHistFile';*
$!
$EXIT:
$ exit !GET_LIBHIST_INFO
$endsubroutine


$!===========================================================================
$CREATE_GENHIST_FILE:subroutine
$ dbgtrace "CREATE_GENHIST_FILE"
$
$ outFile = p1
$ elemList = p2
$!
$ DEFAULT_GEN_SEQ_TT = "50" !!  (tt:50 by default, use to enforce gen order)
$
$ open /write fOut 'outFile'
$!
$ descGenFile = "CMSLIB.TMP_DESCGEN"
$!
$ STS_CMS_NOELE == "%X109C8558" !!empty lib
$
$ set noon
$ cms show gen /desc 'elemList' /out='descGenFile'
$ cmsSts = $STATUS
$ set on
$
$ if (cmsSts .eqs. STS_CMS_NOELE) then  type NL: /out='descGenFile'
$
$ open /read fDescGen 'descGenFile'
$ line=""
$ elem = ""
$ histSeqKey = ""
$
$ prevElem = ""
$ prevHistSeqKey = ""
$!
$SKIP_HEAD_DESCGEN:
$ read/end=ENDDO_DESCGEN  fDescGen line
$ read/end=ENDDO_DESCGEN  fDescGen line
$ read/end=ENDDO_DESCGEN  fDescGen line
$!
$
$DO_DESCGEN:
$   line=""
$   read/end=ENDDO_DESCGEN  fDescGen line
$   if (line .eqs. "") then goto NEXT_DESCGEN
$!
$   call PARSE_GEN_REC
$   if (g_genGotNextElem) then elem = g_genElem
$   if (.not. g_genGotRec) then goto NEXT_DESCGEN
$   if (g_gen .eqs. "") then goto NEXT_DESCGEN
$!
$   if (g_genIsTruncated)
$   then
$     logmsg "W|TRUNCATED: remark truncated for generation ",-
        g_genElem, " /GEN=",g_gen
$   endif
$
$GOT_GEN:
$   dbgmsg "DBG|DESC:genElem:",g_genElem,"|gen:",g_gen,"|",g_genUser,"|",g_genTime,"|",g_genRemark
$
$   !!-- histSeqKey: yyyymmddhhmmsstt
$   !!--
$   call GET_SEQTIME "''g_genTime'"
$   histSeqKey = f$extr(0, f$len(g_seqTime)-2, g_seqTime) + DEFAULT_GEN_SEQ_TT
$
$   !!-- if same histSeqKey as prev for the same elem -- decrement to keep hist order
$   !!--
$   if (elem .eqs. prevElem -
        .and. histSeqKey .eqs. prevHistSeqKey)
$   then
$      prevSeqTT = f$extr(f$len(prevHistSeqKey)-2,2, prevHistSeqKey)
$      seqTT = f$extr(1, 2, f$str(100 + f$int(prevSeqTT) - 1))
$      histSeqKey = f$extr(0, f$len(histSeqKey)-2, histSeqKey) + seqTT
$   endif
$
$   genHistRec = histSeqKey -
                 +CHAR_PIPE+ g_genElem -
                 +CHAR_PIPE+ g_gen + ":" -
                 +CHAR_PIPE -
                 +CHAR_PIPE -
                 +CHAR_PIPE -
                 +CHAR_PIPE -
                 +CHAR_PIPE -
                 +CHAR_PIPE+ CHAR_DBLQUOTE+CHAR_DBLQUOTE
$   write fOut genHistRec
$!
$NEXT_DESCGEN:
$   prevElem = elem
$   prevHistSeqKey = histSeqKey
$   goto DO_DESCGEN
$ENDDO_DESCGEN:
$ if (f$trnlnm("fDescGen") .nes. "") then close fDescGen
$ if (f$search(descGenFile) .nes. "") then del /nolog/noconf 'descGenFile';*
$!
$ if (f$trnlnm("fOut") .nes. "") then close fOut
$
$ QKey = "/key=(pos:1,siz:'f$len(histSeqKey))"
$ if (histSeqKey .nes. "") then sort 'outFile' 'outFile';
$ purge /nolog /noconf 'outFile'
$!
$EXIT:
$ if (f$trnlnm("fOut") .nes. "") then close fOut
$!
$ exit  !CREATE_GENHIST_FILE
$endsubroutine


$!===========================================================================
$CREATE_CLASSHIST_FILE:subroutine
$ dbgtrace "CREATE_CLASSHIST_FILE"
$
$ outFile = p1
$ histCommitsFile = p2
$ classList = p3
$
$ DEFAULT_CLASS_SEQ_TT = "99"  !! should be .gt. DEFAULT_GEN_SEQ_TT
$
$!
$ open /write fOut 'outFile'
$!
$ genClassFile = "CMSLIB.TMP_GENCLASS"
$ histInfoFile = "CMSLIB.TMP_HISTINFO"
$!
$ STS_CMS_NOCLS == "%X109C8508" !!lib has no classes
$
$ set noon
$ cms show class /content 'classList' /out='genClassFile'
$ cmsSts = $STATUS
$ set on
$
$ if (cmsSts .eqs. STS_CMS_NOCLS) then  type NL: /out='genClassFile'
$
$ open /read fGenClass 'genClassFile'
$ line=""
$!
$ class = ""
$ classSeqKey = ""
$ classTime = ""
$ classUser = ""
$ classRemark = ""
$ classIdx = 0
$
$SKIP_HEAD_GENCLASS:
$ read/end=ENDDO_GENCLASS  fGenClass line
$ read/end=ENDDO_GENCLASS  fGenClass line
$ read/end=ENDDO_GENCLASS  fGenClass line
$!
$DO_GENCLASS:
$   line=""
$   read/end=ENDDO_GENCLASS  fGenClass line
$   if (line .eqs. "") then goto NEXT_GENCLASS
$!
$   call PARSE_GENCLASS_REC
$   if (g_genclassIsName)
$   then
$     if (class .nes. "")
$     then
$       histSeqKey = classSeqKey
$       histRemark = classRemark
$       histTime = classTime
$       histUser = classUser
$       histElem = ""
$       histGen = ""
$       histBlobId = 0
$       gosub GOSUB_WRITE_CLASSHIST_REC  !! write previous class rec
$     endif
$
$     class = g_genclassName
$     classRemark = g_genclassRemark
$     classIdx = classIdx + 1
$
$     !!-- track class member generations' insert time (or commit time)
$     !!-- the max time stamp can be used as commit time for the whole class
$     !!-- bump the class' time-seq up, so it's after all its member gens
$     !!--
$     classSeqKey = ""
$
$     goto NEXT_GENCLASS
$   endif
$
$   !!-- process class memeber generation
$   if (g_genclassElem .eqs. "") then goto NEXT_GENCLASS
$
$   dbgmsg "DBG|GENCLASS:class:",g_genclassName,"|",g_genclassElem,"|",g_genclassGen,"|",g_genclassRemark
$
$   histElem = g_genclassElem
$   histGen = g_genclassGen
$
$   !!-- get class generation's blob-id
$   !!--
$   call GET_HISTCOMMITS  "''histCommitsFile'" "" "''g_genclassElem'" "''g_genclassGen'"
$   !!TOADD:: check if found hist commit (g_histSeqKey .nes. "")
$
$   if (g_histSeqKey .gts. classSeqKey)
$   then
$     classSeqKey = f$extr(0,f$len(g_histSeqKey) - 2, g_histSeqKey) + DEFAULT_CLASS_SEQ_TT
$     classTime  = g_histTime
$     classUser = g_histUser
$   endif
$
$   histBlobId = g_histBlobId
$
$
$   !!-- get class generation's insert date (most recent if many)
$   !!--
$   pipe cms sh hist /trans=insert 'g_genclassElem' -
      | search sys$input " GENERATION " ," ''g_genclassElem'(''g_genclassGen') ", -
        " ''class' """ /match=and /out='histInfoFile'
$
$   open /read fHistInfo 'histInfoFile'
$   histTime = ""
$   histUser = ""
$   histRemark = ""
$DO_CLASSGENINFO:
$   line = ""
$   read /END=ENDDO_CLASSGENINFO fHistInfo line
$   call PARSE_LIBHIST_REC
$
$   histTime = g_libhistTime
$   histUser = g_libhistUser
$   histRemark = f$elem(1,CHAR_DBLQUOTE, g_libhistCommand)
$
$ENDDO_CLASSGENINFO:
$   if (f$trnlnm("fHistInfo") .nes. "") then close fHistInfo
$   if (f$search(histInfoFile) .nes. "") then del /nolog /noconf 'histInfoFile';*
$!
$   !!TOADD:: check if got any libhist (histTime .nes. "")
$
$   !!-- histSeqKey: yyyymmddhhmmsstt
$   !!--
$   call GET_SEQTIME "''histTime'"
$   histSeqKey = g_seqTime
$
$   if (histSeqKey .gts. classSeqKey)
$   then
$     classSeqKey = f$extr(0,f$len(histSeqKey) - 2, histSeqKey) + DEFAULT_CLASS_SEQ_TT
$
$     classTime = histTime
$     classUser = histUser
$   endif
$
$   gosub GOSUB_WRITE_CLASSHIST_REC
$
$!
$NEXT_GENCLASS:
$   goto DO_GENCLASS
$ENDDO_GENCLASS:
$
$ if (class .nes. "" -
      .and. classSeqKey .nes. "")
$ then
$   histSeqKey = classSeqKey
$   histRemark = classRemark
$   histTime = classTime
$   histUser = classUser
$   histElem = ""
$   histGen = ""
$   histBlobId = 0
$   gosub GOSUB_WRITE_CLASSHIST_REC   !! write the last class's rec
$ endif
$
$ if (f$trnlnm("fGenClass") .nes. "") then close fGenClass
$ if (f$search(genClassFile) .nes. "") then del /nolog/noconf 'genClassFile';*
$!
$ if (f$trnlnm("fOut") .nes. "") then close fOut
$!
$ sort 'outFile' 'outFile';
$ purge /nolog /noconf 'outFile'
$!
$EXIT:
$ if (f$trnlnm("fOut") .nes. "") then close fOut
$!
$ exit  !CREATE_CLASSHIST_FILE

$!-------------------------------
$GOSUB_WRITE_CLASSHIST_REC:
$ dbgtrace "GOSUB_WRITE_CLASSHIST_REC"
$
$ if (class .nes. "" -
      .and. histSeqKey .nes. "")
$ then
$   classHistRec = CHAR_PIPE -
                 +CHAR_PIPE -
                 +CHAR_PIPE+ class -
                 +CHAR_PIPE+ f$str(histBlobId) -
                 +CHAR_PIPE+ histSeqKey -
                 +CHAR_PIPE+ histElem -
                 +CHAR_PIPE+ histGen -
                 +CHAR_PIPE+ histTime -
                 +CHAR_PIPE+ histUser -
                 +CHAR_PIPE+ CHAR_DBLQUOTE+ histRemark +CHAR_DBLQUOTE
$
$   write fOut classHistRec
$ endif
$
$ return

$endsubroutine !CREATE_CLASSHIST_FILE


$!===========================================================================
$GET_CURGEN_ANC:subroutine
$ dbgtrace "GET_CURGEN_ANC"
$
$ elem = p1
$ gen = p2
$ ancIdx = f$int(p3)
$ if (ancIdx .eq. 0) then ancIdx = 1  !!-- first immediate ancestor gen
$
$ !!-- init retvalues
$ !!--
$ g_curElem == ""
$ g_curGen == ""
$ g_curTime == ""
$ g_curUser == ""
$ g_curRemark == ""
$ g_ancElem == ""
$ g_ancGen == ""
$ g_ancTime == ""
$ g_ancUser == ""
$ g_ancRemark == ""
$
$ !!-- process ancestors of the current generation
$ !!--
$ ancGenFile = "''elem'_''gen'_ANC"
$!
$ cms show gen /anc 'elem' /gen='gen' /out='ancGenFile'
$!
$ open /read fAncGen 'ancGenFile'
$!
$ line=""
$SKIP_HEAD_ANCGEN:
$ read/end=ENDDO_ANCGEN  fAncGen line
$ read/end=ENDDO_ANCGEN  fAncGen line
$ read/end=ENDDO_ANCGEN  fAncGen line
$!
$ genIdx = 0
$
$DO_ANCGEN:
$   line=""
$   read/end=ENDDO_ANCGEN  fAncGen line
$!
$   call PARSE_GEN_REC
$   if (g_genGotNextElem) then elem = g_genElem
$   if (.not. g_genGotRec) then goto NEXT_ANCGEN
$   if (g_gen .eqs. "") then goto NEXT_ANCGEN
$!
$GOT_ANCGEN:
$   dbgmsg "DBG|ANC:genElem:",g_genElem,"|gen:",g_gen,"|",g_genUser,"|",g_genTime,"|",g_genRemark
$!
$   if (genIdx .lt. ancIdx)
$   then
$     if (genIdx .eq. 0)
$     then
$       g_curElem == g_genElem
$       g_curGen == g_gen
$       g_curTime == g_genTime
$       g_curUser == g_genUser
$       g_curRemark == g_genRemark
$     endif
$     goto NEXT_ANCGEN
$!
$   else
$     if (genIdx .eq. ancIdx)
$     then
$       g_ancElem == g_genElem
$       g_ancGen == g_gen
$       g_ancTime == g_genTime
$       g_ancUser == g_genUser
$       g_ancRemark == g_genRemark
$     endif
$     goto ENDDO_ANCGEN
$   endif
$!
$NEXT_ANCGEN:
$   if (g_gen .nes. "") then genIdx = genIdx + 1
$   goto DO_ANCGEN
$ENDDO_ANCGEN:
$ if (f$trnlnm("fAncGen") .nes. "") then close fAncGen
$ if (f$search(ancGenFile) .nes. "") then del /nolog/noconf 'ancGenFile';*
$!
$EXIT:
$ exit !GET_CURGEN_ANC
$endsubroutine


$!===========================================================================
$GET_HISTCOMMITS:subroutine
$ dbgtrace "GET_HISTCOMMITS"
$
$ histCommitsFile = p1
$ seqKey = p2
$ elem = p3
$ gen = p4
$
$ !!-- init retvals (initialize only the key field)
$ !!--
$ g_histSeqKey == ""
$
$!
$ if (seqKey .nes. "")
$ then
$   searchKey = seqKey +CHAR_PIPE
$   keySize = f$len(searchKey)
$   keyInfo = "/key=(pos:1, size:''keySize')"
$
$   searchOutFile = "COMMITS.TMP_HIS"
$ else
$   searchKey = CHAR_PIPE+ elem +CHAR_PIPE+ "''gen':"
$   searchOutFile = "''elem'_''gen'_HIS"
$ endif
$
$!
$ STS_SEARCH_NOMATCHES = "%X08D78053"
$!
$ set noon
$ search /nowarn 'histCommitsFile' "''searchKey'" 'keyInfo' /out='searchOutFile'
$ stsSearch = $STATUS
$ set on
$ if (stsSearch .ne. 1)
$ then
$   goto END_SEARCHOUT
$ endif
$
$ open /read fSearchOut 'searchOutFile'
$
$ line = ""
$ read/end=END_SEARCHOUT fSearchOut line
$!
$ !!-- parse the histCommits record, fill the global fields
$ !!--
$ call PARSE_HISTCOMMITS_REC
$!
$END_SEARCHOUT:
$ if (f$trnlnm("fSearchOut") .nes. "") then close fSearchOut
$ if (f$search(searchOutFile) .nes. "") then del /nolog /noconf 'searchOutFile';*
$
$EXIT:
$  exit !GET_HISTCOMMITS
$endsubroutine


$!===========================================================================
$GET_XREF_CLASSBRANCH:subroutine
$ dbgtrace "GET_XREF_CLASSBRANCH"
$
$ xrefClassBranchFile = p1
$ class = p2
$
$ !!-- init retvals (initialize only the key field)
$ !!--
$ g_xrefClassBranch == ""
$
$!
$ searchKey =  "''class':"
$ keySize = f$len(searchKey)
$ keyInfo = "/key=(pos:1, size:''keySize')"
$
$ searchOutFile = "CLASSES.TMP_XREF"
$
$!
$ STS_SEARCH_NOMATCHES = "%X08D78053"
$!
$ set noon
$ search /nowarn 'xrefClassBranchFile' "''searchKey'" 'keyInfo' /out='searchOutFile'
$ stsSearch = $STATUS
$ set on
$ if (stsSearch .ne. 1)
$ then
$   goto END_SEARCHOUT
$ endif
$
$ open /read fSearchOut 'searchOutFile'
$
$ line = ""
$ read/end=END_SEARCHOUT fSearchOut line
$!
$ !!-- parse the class branch xref record, fill the global fields
$ !!--
$ call PARSE_XREF_CLASSBRANCH_REC
$!
$END_SEARCHOUT:
$ if (f$trnlnm("fSearchOut") .nes. "") then close fSearchOut
$ if (f$search(searchOutFile) .nes. "") then del /nolog /noconf 'searchOutFile';*
$
$EXIT:
$  exit !GET_XREF_CLASSBRANCH
$endsubroutine


$!===========================================================================
$GET_SEQTIME:subroutine
$ dbgtrace "GET_SEQTIME"
$!
$ timestamp = p1
$ !!-- init retval
$ !!--
$ g_seqTime == ""
$
$ !!-- yyyymmddhhmmsstt
$ g_seqTime == f$cvtime(timestamp,"COMPARISON") -
               - "-" - "-" - ":" - ":" - ":" - " " - "."
$
$
$EXIT:
$ exit !GET_SEQTIME
$endsubroutine


$!===========================================================================
$PARSE_HISTCOMMITS_REC:subroutine
$ dbgtrace "PARSE_HISTCOMMITS_REC"
$
$ histCommitsRec = line
$
$ !dbgmsg "DBG|PARSE_HISTCOMMITS_REC:",histCommitsRec,"|"
$
$ !!-- init retvalues
$ !!--
$ g_histSeqKey == ""
$ g_histElem == ""
$ g_histGen == ""
$ g_histAncGen == ""
$ g_histCommitId == ""
$ g_histAncId == ""
$ g_histBlobId == ""
$ g_histTime == ""
$ g_histUser == ""
$ g_histRemark == ""
$
$!
$ g_histSeqKey == f$elem(0,CHAR_PIPE, histCommitsRec)
$ g_histElem == f$elem(1,CHAR_PIPE, histCommitsRec)
$
$ genVal = f$elem(2,CHAR_PIPE, histCommitsRec)
$ g_histGen == f$elem(0,":",genVal)
$ g_histAncGen == f$elem(1,":",genVal)
$
$ g_histCommitId == f$elem(3,CHAR_PIPE, histCommitsRec)
$ g_histAncId == f$elem(4,CHAR_PIPE, histCommitsRec)
$ g_histBlobId == f$elem(5,CHAR_PIPE, histCommitsRec)
$ g_histTime == f$elem(6,CHAR_PIPE, histCommitsRec)
$ g_histUser == f$elem(7,CHAR_PIPE, histCommitsRec)
$
$ g_histRemark == f$elem(1,CHAR_DBLQUOTE, histCommitsRec)
$
$
$EXIT:
$ exit !PARSE_HISTCOMMITS_REC
$endsubroutine


$!===========================================================================
$PARSE_CLASSHIST_REC:subroutine
$ dbgtrace "PARSE_CLASSHIST_REC"
$
$ classHistRec = line
$
$ !dbgmsg "DBG|PARSE_CLASSHIST_REC:",classHistRec,"|"
$
$ !!-- init retvalues
$ !!--
$ g_classIsName == ""
$ g_classBranch == ""
$ g_classSeqKey == ""
$ g_class == ""
$ g_classBlobId == 0
$ g_classHistSeqKey = ""
$ g_classElem == ""
$ g_classGen == ""
$ g_classTime == ""
$ g_classUser == ""
$ g_classRemark == ""
$
$!
$ g_classBranch == f$elem(1,CHAR_PIPE, classHistRec)
$ g_classSeqKey == f$elem(2,CHAR_PIPE, classHistRec)
$ g_class == f$elem(3,CHAR_PIPE, classHistRec)
$ g_classBlobId == f$elem(4,CHAR_PIPE, classHistRec)
$ g_classHistSeqKey == f$elem(5,CHAR_PIPE, classHistRec)
$ g_classElem == f$elem(6,CHAR_PIPE, classHistRec)
$ g_classGen == f$elem(7,CHAR_PIPE, classHistRec)
$ g_classTime == f$elem(8,CHAR_PIPE, classHistRec)
$ g_classUser == f$elem(9,CHAR_PIPE, classHistRec)
$
$ g_classRemark == f$elem(1,CHAR_DBLQUOTE, classHistRec)
$
$ g_classIsName == (g_class .nes. "" .and. g_classBlobId .eq. 0)
$
$EXIT:
$ exit !PARSE_CLASSHIST_REC
$endsubroutine


$!===========================================================================
$PARSE_XREF_CLASSBRANCH_REC:subroutine
$ dbgtrace "PARSE_XREF_CLASSBRANCH_REC"
$
$ xrefClassBranchRec = line
$
$ !dbgmsg "DBG|PARSE_XREF_CLASSBRANCH_REC:",xrefClassBranchRec,"|"
$
$ !!-- init retvalues
$ !!--
$ g_xrefClass == ""
$ g_xrefClassBranch == ""
$
$!
$ xrefVal = f$elem(0,CHAR_PIPE, xrefClassBranchRec)
$ g_xrefClass == f$elem(0,":",xrefVal)
$ g_xrefClassBranch == f$elem(1,":",xrefVal)
$
$EXIT:
$ exit !PARSE_XREF_CLASSBRANCH_REC
$endsubroutine


$!===========================================================================
$PARSE_GENCLASS_REC:subroutine
$ dbgtrace "PARSE_GENCLASS_REC"
$!
$ genClassRec = line
$
$ !dbgmsg "DBG|PARSE_GENCLASS_REC:",genClassRec,"|"
$!
$ !!-- init retvalues
$ !!--
$ g_genclassElem == ""
$ g_genclassGen == ""
$
$ g_genclassIsName == ( f$extr(0, 1, genClassRec) .nes. CHAR_SPACE )
$!
$ if (genClassRec .eqs. "") then goto EXIT
$!
$ if (g_genclassIsName)
$ then
$   g_genclassName == f$edit(f$elem(0,CHAR_DBLQUOTE,genClassRec),"TRIM,LOWERCASE")
$   g_genclassRemark == f$elem(1,CHAR_DBLQUOTE,genClassRec)
$   goto EXIT
$ endif
$!
$ xline = f$edit(genClassRec, "COMPRESS")
$!
$ g_genclassElem == f$edit(f$elem(1, CHAR_SPACE, xline), "TRIM,LOWERCASE")
$ if (g_genclassElem .eqs. "") then goto EXIT
$
$ g_genclassGen == f$elem(2, CHAR_SPACE, xline)
$!
$EXIT:
$ exit  !PARSE_GENCLASS_REC
$endsubroutine


$!===========================================================================
$PARSE_GEN_REC:subroutine
$ dbgtrace "PARSE_GEN_REC"
$!
$ genRec = line
$
$ !dbgmsg "DBG|PARSE_GEN_REC:",genRec,"|"
$!
$ !!-- init retvalues
$ !!--
$ if ("''g_genGotNextElem'" .eqs. "")
$ then
$   g_genGotNextElem == "F"
$   g_genElem == ""
$   g_genGotRec == "T"
$ endif
$
$ if (g_genGotRec .or. g_genGotNextElem)
$ then
$   g_genGotNextElem == "F"
$   g_genGotRec == "F"
$   g_gen == ""
$   g_genTime == ""
$   g_genUser == ""
$   g_genRemark == ""
$   g_genIsTruncated == "F"
$   g_genRecBuf == ""
$   g_genRecBufLen == 0
$ endif
$
$ if (genRec .eqs. "") then goto REC_EMPTY
$ if (f$extr(0, 1, genRec) .nes. CHAR_SPACE ) then goto REC_ELEM
$ goto REC_GEN
$
$REC_EMPTY:
$ goto EXIT
$
$REC_ELEM:
$ g_genElem == f$edit(genRec,"TRIM,LOWERCASE")
$ g_genGotNextElem == (g_genElem .nes. "")
$ g_genGotRec == "F"
$ if (.not. g_genGotNextElem) then goto ERROR
$ goto EXIT
$
$REC_GEN:
$ if (g_genElem .eqs. "") then goto ERROR
$
$ !!-- Gen record may be wrapped on a long Remark ("remark").
$ !!-- Max length of a Gen record is 130 chars, but it's wrapped at whole words.
$ !!-- wrapped chunks are offset with 13 spaces.
$ !!-- Join (using a space) all the chunks (until dbl-quote terminated)
$ !!-- into a whole Gen record, then parse it.
$ !!-- Truncate the remark to the size of a whole Gen record.
$ !!-- When remark is too long it can still trip DCL error ('help /mess TKNOVF'),
$ !!-- in such case try to decrease the REMARK_MAXLEN.
$ !!--
$ GEN_REC_MAXLEN = 130
$ GEN_RECBUF_MAXLEN = 1024 - GEN_REC_MAXLEN
$ WRAPPEDLINE_OFFSET = 13
$ REMARK_MAXLEN = GEN_REC_MAXLEN
$
$ genRecLen = f$len(genRec)
$ if (f$extr(WRAPPEDLINE_OFFSET-1, 1, genRec) .eqs. CHAR_SPACE -
      .and. f$edit(f$extr(0,WRAPPEDLINE_OFFSET, genRec), "COMPRESS") .eqs. CHAR_SPACE)
$ then
$   genRec = f$extr(WRAPPEDLINE_OFFSET, genRecLen, genRec)
$   genRecLen = genRecLen - WRAPPEDLINE_OFFSET
$ endif
$ hasEndingQuote = (genRecLen .gt. 0 -
                    .and. f$extr(genRecLen-1, 1, genRec) .eqs. CHAR_DBLQUOTE)
$ if ((g_genRecBufLen + 1 + genRecLen) .ge. GEN_RECBUF_MAXLEN)
$ then
$   genRecLen = GEN_RECBUF_MAXLEN - g_genRecBufLen - 1
$   genRec = f$extr(0, genRecLen, genRec)
$   g_genIsTruncated == "T"
$ endif
$ g_genRecBuf == g_genRecBuf + CHAR_SPACE + genRec
$ g_genRecBufLen == g_genRecBufLen + 1 + genRecLen
$
$ g_genGotRec == (hasEndingQuote)
$ if (.not. g_genGotRec) then goto EXIT
$
$ xline = f$edit(g_genRecBuf, "COMPRESS")
$!
$ g_gen == f$elem(1, CHAR_SPACE, xline)
$ if (g_gen .eqs. "") then goto EXIT
$
$ g_genTime == f$elem(2, CHAR_SPACE, xline) -
            + ":" + f$elem(3, CHAR_SPACE, xline)
$ g_genUser == f$elem(4, CHAR_SPACE, xline)
$
$ offset = f$loc(CHAR_DBLQUOTE, g_genRecBuf)+1
$ endPos = g_genRecBufLen
$ if (hasEndingQuote) then endPos = g_genRecBufLen-1
$ len = endPos - offset
$ if (len .gt. REMARK_MAXLEN)
$ then
$    len = REMARK_MAXLEN
$    g_genIsTruncated == "T"
$ endif
$ remark = f$extr(offset, len, g_genRecBuf)
$ g_genRemark == remark
$
$!
$EXIT:
$ if (g_genGotRec)
$ then
$   g_genRecBuf == ""
$   g_genRecBufLen == 0
$ endif
$ exit  !PARSE_GEN_REC

$ERROR:
$ exit 4
$endsubroutine


$!===========================================================================
$PARSE_LIBHIST_REC:subroutine
$ dbgtrace "PARSE_LIBHIST_REC"
$
$ libHistRec = f$edit(line,"TRIM")
$
$ !!-- init retvals
$ !!--
$ g_libhistTime == ""
$ g_libhistUser == ""
$ g_libhistCommand == ""
$
$!
$ date = f$elem(0,CHAR_SPACE,libHistRec)
$ time = f$elem(1,CHAR_SPACE,libHistRec)
$ user = f$elem(2,CHAR_SPACE,libHistRec)
$
$ g_libhistTime == date + ":" + time
$ g_libhistUser == user
$!
$ offset = f$len(date) +1+ f$len(time) +1+ f$len(user) +1
$ g_libhistCommand == f$extr(offset, f$len(libHistRec), libHistRec)
$
$EXIT:
$ exit !PARSE_LIBHIST_REC
$endsubroutine


$!===========================================================================
$GET_TOTSECS_TIME:subroutine
$ dbgtrace "GET_TOTSECS_TIME"
$
$ UNIX_EPOCH = "01-JAN-1970 00:00:00"
$
$ end = f$cvtime("","ABSOLUTE")
$ if (p1 .nes. "") then -
    end = f$cvtime(p1,"ABSOLUTE")
$
$ start = UNIX_EPOCH
$ if (p2 .nes. "") then -
    start = f$cvtime(p2,"ABSOLUTE")
$
$ !!-- init retvals
$ !!--
$ g_totSecsTime == 0
$
$!
$ !dbgmsg "DBG|end:",end,"|start:",start
$
$!--------------------------
$!
$ startYear = f$cvtime(start,,"YEAR")
$ endYear = f$cvtime(end,,"YEAR")
$
$ year = endYear
$ totsecs = f$cvtime(end,,"SECONDOFYEAR")
$
$DO_YEARSECS:
$   if (year .le. startYear) then goto ENDDO_YEARSECS
$   year = year - 1
$   nsecs = f$cvtime("31-DEC-''year' 23:59:59",,"SECONDOFYEAR") + 1
$!
$   !dbgmsg "DBG|year:",year,"|nsecs:",nsecs
$!
$   totsecs = totsecs + nsecs
$!
$NEXT_YEARSECS:
$   goto DO_YEARSECS
$ENDDO_YEARSECS:
$!
$ !dbgmsg "DBG|totsecs:", totsecs
$!
$ g_totSecsTime == totsecs
$
$EXIT:
$ exit !GET_TOTSECS_TIME
$endsubroutine


$!============================================================================
$USAGE_DETAILS:subroutine
$ gosub LICENSE
$
$ logmsg "I|USAGE_DETAILS:"
$
$ type sys$input
$DECK
INFO:
Utility to export a CMS library into git-fast export format file.

DETAILS:
Maps CMS objects to git objects as follows:
- CMS elements => git files/blobs
- CMS element generations => git commits
- CMS variant generations => git branches/tags
- CMS generation classes => git branches/tags
- CMS groups => NOT MAPPED
- CMS time-stamps => git commit time-stamps

Optionally, CMS classes may be individually mapped to user-specified git
branches (e.g. release version classes => commits on release branch).

Class-branch cross-reference file lists mapping records in the following format:
    "class-name:branch-name|"


RETURNS:
Output export file is created in git-fast export format (Stream-LF, generally
of binary type). The file can be used as input to `git fast-import` command
to create a CMS-exported git repository.

Additionally, creates files `cmslib.commits` and `cmslib.classes` which describe
the CMS library and actually drive the export process. These files can also be
helpful for diagnostic purposes.

On successful completion the $STATUS is set as:
    STS_SUCCESS = "%X10000001"

Otherwise $STATUS is set as:
    STS_ERROR = "%X10000002"

EXAMPLES:
    $ @exportcms-git [.testlib] testlib.git-fast

$EOD
$
$ exit !USAGE_DETAILS

$LICENSE:
$ logmsg "I|LICENSE:"
$
$ type sys$input
$DECK
-----------------------------------------------------------------------------
Copyright (c) 2018, Artur Shepilko, <cms-export@nomadbyte.com>.

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
