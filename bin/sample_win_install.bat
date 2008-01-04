
::Files that need to be present in the same directory as this bat file:
::  * the apache installer
::  * the ActiveState perl installer
::  * A GBrowse tarball
::  * A BioPerl tarball
::  * The gbrowse install script, gbrowse_netinstall.pl
::
:: put the apache installer's name below
apache_2.2.6-win32-x86-no_ssl.msi /quiet SERVERDOMAIN=example.com SERVERNAME=www.example.com SERVERADMIN=admin@example.com ALLUSERS=1

:: put the ActiveState perl installer's name below
ActivePerl-5.8.8.822-MSWin32-x86-280952.msi /quiet PERL_PATH="Yes"

set PATH=c:\perl\bin;%PATH%


perl gbrowse_netinstall.pl --bioperl_path bioperl-live.tar.gz --gbrowse_path Generic-Genome-Browser.tar.gz

::Uncommenting the following line will open IE to a sample database page
::"C:\Program Files\Internet Explorer\iexplore.exe" http://localhost/cgi-bin/gbrowse/yeast_chr1/?start=80000;stop=120000;ref=I;width=800;version=100;label=Centro%3Aoverview-Genes-ORFs-tRNAs;grid=1
