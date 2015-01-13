cms-export ChangeLog  {#xcmschangelog}
====================


## 0.8.0 - 2015-01-13

- Update docs


## 0.7.0 - 2015-01-09

- Update docs
- Add doxygen support
- Package for public GitHub release


## 0.6.0 - 2014-04-28

- Bugfixes
- Update tests and docs

- __ISSUE__:Class-commit tags are missing when importing into `fossil`.
  - Analysis showed it's a bug in fossil's import logic -- when processesing `git`
    tag statement a `sym-` is not prepended to the generated fossil tag in "T "
    record.
  - WORKAROUND:If exporting for `fossil`, manually edit `exportcms-git.com` and
    in `GOSUB_WRITE_GIT_TAG` prepend `"sym-"` to `commitTag`.

- __ISSUE-FIX__:Empty class export generated extraneous M-records.



## 0.5.0 - 2014-04-12

- Add support for exporting binary CMS elements
- Add more tests
- Add user documentation
- Restructure the main script using subroutines
- Support class-to-branch mapping via xref-file; tag class commits


- __ISSUE__:When CMS contains classes -- export crashes spectacularly with
  "%SYSTEM-F-ACCVIO" stack dump. Platform:IA64 OpenVMS 8.4, CMS:4.5
  - This is a CMS-related problem (`cms show class /cont *`) triggers the crash.
    Looks like it's isolated to IA64/CMS-4.5.
  - FIX: apply DECSET128ECO1 "DECSet 12.8 ECO1"


## 0.4.0 - 2014-03-24

- Export CMS class as a multi-file commit on off-root branch
- Add variant ancestor as first commit on varline branch
- Add build script and update tests


## 0.3.0 - 2014-03-02

- Export variants to off-root varlines -- separate single-file branches
- Export variant-of-variant to off-varline branch
- Include full element name (with generation) in exported remark
- Add test scripts


## 0.2.0 - 2014-02-15

- Export variant generations in git fast-export format
- Add logging and diagnostics
- Force a pre-set remark for the inital commit, expected by fossil

## 0.1.0 - 2014-02-06

- Export CMS mainline generations in git fast-export format
- Support text-type elements only, no binary-type support
- Create exported CMS repo with `fossil` and `git`
