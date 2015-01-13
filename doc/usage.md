
Export OpenVMS CMS library using cms-export {#xcmsusage}
===========================================

`cms-export` is a utility for OpenVMS to export `CMS` library content and revisions
history. `CMS` is a version control system commonly used in OpenVMS environment
(part of `DECset`). `cms-export` utility allows export of a `CMS` library (or a
set of library elements) into a file in [git-fast-export][git-fast]
format, which subsequently can be used to create a repository with an alternative
version management system such as [git][git-scm], [fossil][fossil-scm] etc.

[xcms]: https://github.com/nomadbyte/cms-export "cms-export project space"
[git-fast]: http://git-scm.com/docs/git-fast-export "git-fast export"
[git-scm]: http://git-scm.com  "git distributed SCM"
[fossil-scm]: http://fossil-scm.org  "fossil distributed SCM"



Mapping `CMS` to `git`
---------------------

`CMS` library content is described in terms of __elements__ and
__groups__ -- for file management; __generations__ and __classes__ -- for
revisions management. These concepts, while simple and flexible, do not map fully
onto __repository-commit-tag__ concepts common to many popular distributed source
management systems.

`cms-export` is designed around the following mappings:
- `CMS` elements => `git` files/blobs
- `CMS` element generations => `git` commits
- `CMS` variant generations => `git` branches/tags
- `CMS` generation classes => `git` branches/tags
- `CMS` groups => NOT MAPPED
- `CMS` time-stamps => `git` commit time-stamps*

Optionally, `CMS` classes may be individually mapped to user-specified `git`
branches (e.g. release version classes => commits on release branch).

Output from `cms-export` utility is an export file in [git-fast-export][git-fast]
format as specified for `git fast-import` command input (or `fossil import --git`).

> __NOTE__: Generally `CMS` does not pre-scribe any specific way or use pattern
> to manage content revisions and releases. Thus such approaches are likely to be
> company- or project-specific, especially given the impressive maturity of
> the `CMS`.

`cms-export` utility does not attempt to embrace a wide variety of possible `CMS`
use patterns; the resulting `git` repository is most expressive with the
following `CMS` patterns:
- Mainline revisions (linear development)
- Limited use of variant branching (patch development)
- Use of classes for tagging or release

For the same reason of `CMS` flexibility, only the present structure of `CMS`
library is exported -- that is the following history of transitional structure
changes is NOT directly exported:
- name-changes for element/class/group
- changes to class contents
- element/generation deletions

This is consistent with the actual use of `CMS`, where the presently available
library objects are the only ones accessible (this includes elements/groups, their
generations/classes). Thus `cms-export` directly exports the final `CMS` library
structure, rather than reconstructing it from use history.

> To summarize this -- the `CMS` element generation descendence lines and class
> contents are seen fixed as of the export time.

On `git` side this translates to only __revision commits__ being recorded
explicitly (corresponds to contents of `cms replace` generation), while the
effective structure changes are automatically inferred from the recorded commits.
A `CMS` class is represented as a single `git` commit consisting of multiple files
(corresponds to class' member generations). Moreover, the commit is on its own
branch per class' name. This differs from usual "tagging" approach, but yields
more consistent view of the `CMS` content. Such class-branches may be consolidated
to common branches (as in case of release version classes) by explicitly
cross-referencing the `CMS` classes to corresponding `git` branches using a custom
cross-reference file.

Refer to "APPENDIX: Examples of `CMS-git` mapping" section for details on
specific export scenarios.



Facility: `EXPORTCMS`
---------------------

`exportcms-git.com`
-------------------

Utility to export a `CMS` library into `git-fast` export format file.

> __USAGE__: `exportcms-git.com [libPath] [outFile] [elemList] [classList] [classBranchXref]`


__PARAMETERS:__

To use a defined default value for a parameter specify null-value `""`.

To get usage help specify `"?"`, or `"??"` for more detail.

- `libPath` -- `CMS` library path, DEFAULT = `CMS$LIB:`
- `outFile` --  `git-export` formatted output file (generally of `BINARY` type),
  DEFAULT = `<lib-name>.git-export`
- `elemList` -- `CMS` element expression to export, DEFAULT = `"*.*"`
- `classList` -- `CMS` class expression to export, DEFAULT = `"*"`
- `classBranchXref` -- cross-reference file to map `CMS` classes to `git` branches,
  DEFAULT = `""`

Class-branch cross-reference file lists mapping records in the following format:

    class-name:branch-name|

Only classes that require mapping need to be listed, otherwise class is mapped to
branch of the same name by default.

If many classes need mapping, output from `cms show class` may be used to prepare
the class-branch cross-reference as a shortcut.


__CONFIGURATION LOGICALS:__

Define these logicals on process-level prior to script execution.

- `VERIFY_EXPORTCMS` -- script verification `1`: ON, `0`: OFF, DEFAULT = `0`
- `DBG_EXPORTCMS` -- enables debug-logging `1-2`: level, `0`: OFF, DEFAULT = `0`
- `LOG_OUTPUT` -- defines logging output device, DEFAULT = `SYS$OUTPUT:`
- `ERR_OUTPUT` -- defines error output device, DEFAULT =`SYS$ERROR:`
- `DBG_OUTPUT` -- defines debug output device, DEFAULT = `LOG_OUTPUT:`


__RETURNS:__

Output export file is created in `git-fast` export format (Stream-LF, generally
of `BINARY` type). The file can be used as input to `git fast-import` command
to create a `CMS`-exported `git` repository.

Additionally, creates files `cmslib.commits` and `cmslib.classes` which describe
the `CMS` library and actually drive the export process. These files can also be
helpful for diagnostic purposes.

On successful completion the `$STATUS` is set as:

    STS_SUCCESS = "%X10000001"

Otherwise `$STATUS` is set as:

    STS_ERROR = "%X10000002"


__EXAMPLES:__

    $ @exportcms-git [.testlib] testlib.git-fast



Troubleshooting
---------------

It is recommended to run the supplied tests prior to attempting export of the
actual `CMS` library. The tests are run as part of `cms-export` build process;
each test exports a local `CMS` test library and results in a `git-fast` file
which can be examined or imported to create a `git` repo.

However even with all tests passing, export of the actual `CMS` library may fail
for some reasons due to library complexity, internal limitations etc..

> __NOTE__: Should export process fail while running from a command-prompt,
> some output or temporary files may remain open; re-running the script may
> seemingly complete successfully, however the resulting output may be empty or
> incorrect.
>
> It is recommended to run export either from a batch queue or from a new `spawn`
> sub-process -- this should provide a consistent starting environment.


__ISSUE__: Export fails with error from `CMS` facility.

ACTION: Export process needs `READ` access to `CMS` library elements,
generations, classes, and history. Additionally, it needs to be able to fetch
element generations in order to export the generation's content.
- Check if user account that executes the export has `READ` access to the
 `CMS` library contents


__ISSUE__: Export fails with error from `RMS` facility.

ACTION: Most of the internal export operations are file-bound and do not
require special privileges. Export process creates a number of temporary files
and needs `READWRITE` access to its default directory.
- Check if user account that executes the export has `READWRITE` access to the
  default directory
- Check if the default device has sufficient free space


__ISSUE__: Export fails with process, IO, or other quota exceeded.

ACTION: Export process essentially does IO and in case of a large `CMS`
library may exceed its allotted IO quotas.
- Check if user account that executes the export has sufficient IO quotas


__ISSUE__: Export shows or fails with `DCL` errors or warnings.

ACTION: Export script manipulates text strings and assumes that elements,
variants, classes, and remarks have a reasonable length to fit in a single
string supported by `DCL` (which has been expanded several times in the history
of OpenVMS).
- Confirm whether it is the case of long strings -- if it is not forthcoming from
  the warning/error itself, you may approximate the problem element/generation,
  remark or class by examining the intermediate files `cmslib.commits` and
  `cmslib.classes`
- If necessary, truncate the unusually long remark by editing the export script's
  `PARSE_`  subroutines relevant to the problem object.


> __NOTE__: In case in-depth diagnostic is needed, turn on either debug statements
> or the full-blown verify mode. See "EXPORTCMS Parameters" section for details.


__If your `CMS` library export requires some additional considerations, you may
contact us for possible work-arounds or an alternative custom solution if needed.
See the "Feedback" section for details.__



Feedback
--------

We appreciate user feedback and hope `cms-export` will be of help to expand the
reach of your OpenVMS-based processes and applications to other platforms.

Let us know your experience with `cms-export`, any bugs found, contributions, or
improvement features. Currently, [cms-export project space][xcms] is the preferred
place to consolidate the interaction about it. Alternatively, you may direct
your feedback to [cms-export\@at\@nomadbyte.com](mailto:cms-export@at@nomadbyte.com) .



APPENDIX: Examples of `CMS-git` mapping
-----------------------------------------

__New `CMS` element => `git` file commit__

- New `CMS` element is added to the `git` repository as a new file
- `git` commit remark includes `CMS` generation name `"(elem-name;gen):Remark"`

  > __NOTE__: `CMS` commit time T (local) is NOT converted to `git` commit time
  > T(UTC), instead it is set directly equal, thus does not take into account the
  > time-zone and daylightsaving shifts.


      (CMS:mainline) CREATE ELEM              (git:master) add/commit
      --+---------------------------->    =>   --+------------------------>
        T1:new-elem.dat/(1) ("Remark")           T1:new-elem.dat ("git-Remark")



__Update `CMS` generation => `git` file commit__

- New `CMS` element generation is recorded as a `git` commit that includes only
  a single file change.


      (CMS:mainline) REPLACE                   (git:master) commit
      --+---------------------------->    =>   --+------------------------>
        T2:new-elem.dat/(2) ("Remark")           T2:new-elem.dat ("Remark")



__New `CMS` mainline-variant => `git` new branch commit__

- `CMS` variant off-mainline results in a new `git` off-root branch named after
  the element's varline `"var-(elem-name;varline)"`
- First commit of the new branch corresponds to the variant's mainline-ancestor
  generation (at ancestor's T)
- Variant's commit follows the ancestor's (at variant's T)
- Subsequent variant generations of the same varline are recorded on the same
  `git` varline branch

  > __NOTE__: The new `git` branch contains only a __single__ file and it is the
  > `CMS` element's variant generation.


      (CMS:varline) REPLACE /VAR=A            (git:"var-(new-elem.dat;2a)") commit
      --o---------------------------->    =>  --o------------------------------>
         `-+--------------->                  --o--+------------>
        T2:new-elem.dat/(2)                     T2:new-elem.dat (2)
           T3:new-elem.dat/(2A1)                   T3:new-elem.dat (2A1)


__New variant off a `CMS` variant => `git` new branch commit__

- Variant off a variant generation results in a new off-variant `git` branch
- The new branch forks off the ancestor's commit on 
  the varline


      (CMS:varline) REPLACE /VAR=X          (git:"var-(new-elem.dat;2a2x)") commit
      --o---------------------------->   =>  --o-------------------------------->
         `-1---2----------->                 --o--1--2--------->
                `-+--------------->                   `-+--------------->
                  T4:new-elem.dat/(2A2X1)               T4:new-elem.dat



__Non-empty `CMS` class => `git` branch commit__

- By default a `CMS` class is exported as a new `git` off-root branch, named after
  the class name
- The new branch contains a single commit that includes all files corresponding
  to member generations of the class

  > __NOTE__: `git` commit time is set to the __greatest__ time-stamp of member
  > generations and class creation time-stamps


      (CMS:class) INSERT GEN                   (git:class) commit
      --1--2-----3---4--------------->    =>   -----4--------------------->
                                               -----+------------>
        T1:elem1.dat                                T1:elem1.dat
        T2:elem2.dat                                T2:elem2.dat
        T3:CREATE CLASS
        T4:elem3.dat                                T4:elem3.dat



__Mapped `CMS` classes => `git` tagged branch commit__

- When using class-branch cross-reference several related `CMS` classes may be
  mapped onto a common `git` branch (e.g. release version classes => commits on
  release branch)
- A new `git` branch is created and the individual `CMS` class commits are
  recorded on this branch and tagged after the class names.

  > __NOTE__: If many classes need mapping, output from `cms show class` may be
  > used to prepare the class-branch cross-reference file.

      class-branch.xref
      v1.0:release|
      v1.1:release|
      v1.2:release|


      (CMS) SHOW CLASS                        (git:release) commit /tag
      --1--2-----3------------------>    =>   --1--------------------->
                                              --1---2----3----->
        T1:v1.0                                 T1:v1.0
        T2:v1.1                                 T2:v1.1
        T3:v1.2                                 T3:v1.2


