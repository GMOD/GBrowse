INSTALL NOTES for Microsoft Windows platforms

Installation currently has only been tested on Windows 2000.  If you install
on another platform successfully, please let me know so I can add it to the
list.

Obtain the prerequisite software listed in the INSTALL document.  I advise
using precomiled binaries where available, including Apache, Activestate Perl,
and MySQL.  For installing Perl modules, I recommend using Activestate's 
PPM tool, including for installing BioPerl.  See the INSTALL.WIN document in
BioPerl's top directory for an excellent guide to installing both Perl and
BioPerl.  A PPM build for GBrowse is not yet available, but I plan on
providing one in a future release.  If you find that you cannot follow these
recommendations, you are pretty much on your own, and be sure you have a
compiler :-)

For the installation itself, you will need Microsoft's nmake utility.  It can
be obtained from Microsoft's website at
http://download.microsoft.com/download/vc15/Patch/1.52/W95/EN-US/Nmake15.exe
which will download an installer.  Note that the resulting NMAKE.EXE and
NMAKE.ERR should be in the System32 folder to work properly.

The installation goes mostly as described in the INSTALL document.  In order
for the Makefile to work correctly, when making the Makefile with Makefile.PL,
supply directories with forward slashes (/) as delimiters instead of
backslashes (\) which are usually used in Windows operating systems.  Also, I
recommend using short file names for paths, as the longer filenames have
spaces in them that sometimes cause problems, therefore, the installation
procedure may look something like this:

C:\GENERI~1.47> perl Makefile.PL PREFIX=C:/PROGRA~1/APACHE~1/APACHE
C:\GENERI~1.47> nmake
C:\GENERI~1.47> nmake install

This will copy the GBrowse configuration, html, and cgi files to the correct
directories in the Apache directory.

MySQL notes:
Be sure to set up MySQL as a service as described in the MySQL documentation,
so that MySQL is started up on boot and properly shutdown before the operating
system halts.

More notes here, as I figure them out.

Scott Cain
cain@cshl.org
12/27/2002



> > in Bio/Graphics/Browser.pm
> >
> > had to put in "binmode" line in sub generate_image
> >
> > after opeing file handle F, insert this line:
> >
> > binmode F;
