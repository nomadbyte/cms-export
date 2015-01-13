
cms-export: OpenVMS CMS library export-to-git utility {#main}
=====================================================

Overview
--------

`cms-export` is a utility for OpenVMS to export `CMS` library content and revisions
history. `CMS` is a version control system commonly used in OpenVMS environment
(part of `DECset`). Valued for being efficient and time-proven, `CMS` also has its
share of drawbacks -- lack of export options being one of these. `cms-export`
utility allows export of a specified `CMS` library (or a set of library elements)
into a file in [git-fast-export][git-fast] format, which subsequently can be used
to create a repository with an alternative version management system such as
[git][git-scm], [fossil][fossil-scm] etc.

`cms-export` is a free software; the use, copy, and distribution rights are granted
under the terms of the @ref xcmslicense | [MIT License][xcmslicense].

[xcms]: https://github.com/nomadbyte/cms-export "cms-export project space"
[xcmsusage]: doc/usage.md "cms-export Usage"
[xcmslicense]: LICENSE.md "MIT License"
[xcmschangelog]: CHANGELOG.md "cms-export ChangeLog"
[git-fast]: http://git-scm.com/docs/git-fast-export "git-fast export"
[git-scm]: http://git-scm.com  "git distributed SCM"
[fossil-scm]: http://fossil-scm.org  "fossil distributed SCM"


Features
--------

`cms-export` utility may be useful in software development efforts to expand
OpenVMS-specific projects to other platforms for portability or migration
objectives. In fact this utility came to being exactly in process of porting an
in-house developed set of OpenVMS-based applications onto Linux platform.

In such scenarios an OpenVMS-based `CMS` library may be used to populate
source code repositories used for development on other platforms.
`cms-export` utility provides a way to export not only the current state of the
library content but also version/generation history, including defined
releases/classes.

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

Refer to @ref xcmsusage | [cms-export Usage][xcmsusage] page for more details.

Updates and details about the current version listed in
@ref xcmschangelog | [cms-export ChangeLog][xcmschangelog].


Quick Start
-----------

`cms-export` utility is expected to run on OpenVMS system which hosts the `CMS`
library to be exported. In current release the `cms-export` utility essentially
consists of a single DCL script ready to run. However, it would be more robust to
set up `cms-export` from the release package (zip-file), which also includes
tests and user-documentation:

- Download the latest `cms-export` release  __source__ package (zip-file) from
  [cms-export project space][xcms] and extract into a work directory:

      unzip cms-export.zip
      set def [.cms-export]

  > __NOTE__: It is important to perform the extraction (unzip) on the OpenVMS
  > side -- this preserves file attributes (in this case, keeps the Stream-LF
  > record attribute) of some files used for testing, otherwise the tests will
  > fail due to mismatching line-endings.


- Create a build directory and start build script from
  inside it:

      create /dir [.build]
      set def [.build]
      @[-]build clean all test

- OR
  do a logged build (all messages are redirected to a log-file):

      define err_output log_output
      pipe @[-]build clean all test 2>&1 >build.log


- On successful completion all tests have passed and the `cms-export` utility
  is available for use or installation:

      dir [.tests]*.*FAILED
      dir [.tests]*.*PASSED
      dir [.bin]

- Also, you may look at the `git-fast` export files resulting from the completed
  tests -- they correspond to the test `CMS` library exported at each stage of the
  completed test sequence:

      dir [.tests]*.git-fast
      cms set lib [.tests.testlib]

- Once familiar with general `cms-export` operation, __export your own
  `CMS` library__ or just try it with the very same `testlib` as above:

      EXPORTCMS := @[path-to-cmsexport-bin]exportcms-git.com
      create /dir [.work]
      set def [.work]
      cms set lib [path-to-cmslib]
      EXPORTCMS
      dir *.git-fast

- OR
  redirect messages to a log-file:

      define err_output log_output
      pipe EXPORTCMS  2>&1 >exportcms.log


  > __NOTE__: For better use of system resources it is recommended to run export
  > process from a batch queue. This also makes sure the export process starts from
  > a fresh logical environment. When submitting to batch queue, a log-file can be
  > set for the whole batch job.
  >
  > To enable verify or debug statements for the export process, define
  > `VERIFY_EXPORTCMS` or `DBG_EXPORTCMS` process logicals prior to starting the
  > export job.

- Any of the resulting test `git-fast` export file may then be used to create
  a new `git` repository on other platform (e.g. Linux):

      mkdir testlib
      cd testlib
      git init
      git fast-import < ../testlib.git-fast
      git checkout master

  > __NOTE__: In general, the resulting `git-fast` export files are of `BINARY/IMAGE`
  > type, so make sure to properly set the transfer mode if copying these via FTP.
  >
  > Also it may make sense to zip the resulting `git-fast` file before
  > transferring it to other platform, especially when exported `CMS` library is
  > rather big or spanning far-back in-time (a lot of revisions).

Refer to @ref xcmsusage | [cms-export Usage][xcmsusage] page for more details
and advanced use examples.


Support
-------

In its original release the `cms-export` utility has helped us successfully export
`CMS` libraries for our in-house developed OpenVMS applications and set up
Linux-based repositories (we use [fossil][fossil-scm] SCM). So as such,
`cms-export` has already paid back its worth to us, but we would hope it may as
well be suitable for similar projects of fellow OpenVMS developers.

Let us know of your experience, challenges or problems (bugs?) with it -- quite
possible we have dealt with these too and may have work-arounds or may suggest
some alternatives.

A public issue tracker may be eventually set up to address possible user-feedback.
Meanwhile, please direct your feedback to [cms-export GitHub project page][xcms].

Of course, _Fork us on GitHub!_ as it goes to welcome your contribution.

