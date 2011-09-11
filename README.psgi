RUNNING GBROWSE UNDER PSGI/PLACK


INTRODUCTION
---------------------------------------------

Here's a simple approach for installing and running a local instance
of GBrowse leveraging the PSGI/Plack webserver <-> web application stack.
You don't need root access, you don't need Apache, and you don't need
to request any firewall exceptions (for now). Later, you can run this instance
with a variety of HTTP servers: starman, nginx, apache, etc.

Both the current implementation and installer of GBrowse are loosely tied 
to Apache. The installer generates suitable configuration and installation
paths compatible with an Apache deployment.  The implementation is a suite
of CGIs. Although a perfectly reasonable approach, this structure increases
the administrative effort required for running a local instance and 
decreases its portability for use in other environments.

Enter PSGI (Perl Web Server Gateway Interface), a specification for glueing
Perl applications to webservers. Plack is a reference implementation of this
specification.  PSGI as implemented by Plack makes it simple to run Perl-based
applications (even CGI based ones like GBrowse) in a variety of environments.

The core Plack distribution contains a light-weight webserver 
(HTTP::Server::PSGI) and handlers for other environments (Apache, CGI, FCGI,
mod_perl).  Other webservers also implement the PSGI specification, including
the high-performance preforking server Starman.

You can also do cool things via middleware handlers like mapping multiple 
applications to different URLs with ease (how about running the best 10 versions
of GBrowse all without touching Apache config or dealing with library conflicts),
handle tasks like serving static files, mangle requests and responses, etc.

    Read more at: http://plackperl.org


WHAT THIS ISN'T (YET)
---------------------------------------------

This isn't a rewrite of GBrowse using PSGI. It's just some modifications to 
the current GBrowse to make it possible to wrap the CGI components so 
that they can be used via servers that implement the PSGI specification.


CONVENTIONS
---------------------------------------------

1. Installation root

   Our working installation root is ~/gbrowse.

2. No root privileges required.

   You do not need to be root. Ever. In fact, one of the great advantages
   of this approach is the ease with which you can install a local instance.

3. Self-contained, versioned installation paths.

   This tutorial installs everything under a single directory for simplified
   management and configuration.  This path corresponds to the version of GBrowse
   being installed.

   The current version of GBrowse is specified by either environment variables
   and/or the presence of a symlink (~/gbrowse/current -> ~/gbrowse/gbrowse-2.XX).
   If something goes wrong, it's easy to roll back to an older version.

4. Each installation has it's own set of local libraries.

   In keeping with the self-contained non-privileged design gestalt, 
   we'll install all required libraries to a local path tied to the 
   installed version of GBrowse (~/gbrowse/current/extlib).  This makes 
   it dead simple to run many possibly conflicting variants of GBrowse,
   all with their own dedicated suite of libraries.


INSTALLATION
---------------------------------------------

1. Set up your environment.

  // Set an environment variables for the your installation root and the version of GBrowse you are installing.
  > export GBROWSE_ROOT=~/gbrowse
  > export GBROWSE_VERSION=2.40

2. Prepare your library directory.

  // You may need to install the local::lib library first
  > (sudo) perl -MCPAN -e 'install local::lib'

  > mkdir -p ${GBROWSE_ROOT}/${GBROWSE_VERSION}
  > cd ${GBROWSE_ROOT}/${GBROWSE_VERSION}          
  > mkdir extlib ; cd extlib
  > perl -Mlocal::lib=./
  > eval $(perl -Mlocal::lib=./)

3. Check out GBrowse fork with modifications for running under PSGI/Plack

  > cd ${GBROWSE_ROOT}
  > mkdir src ; cd src
  > git clone git@github.com:tharris/GBrowse-PSGI.git
  > cd GBrowse-PSGI.git
  # Here, the wwwuser is YOU, not the Apache user.
  > perl Build.PL --conf         ${GBROWSE_ROOT}/${GBROWSE_VERSION}/conf \
                  --htdocs       ${GBROWSE_ROOT}/${GBROWSE_VERSION}/html \
                  --cgibin       ${GBROWSE_ROOT}/${GBROWSE_VERSION}/cgi \
                  --wwwuser      $LOGNAME \
                  --tmp          ${GBROWSE_ROOT}/${GBROWSE_VERSION}/tmp \
                  --persistent   ${GBROWSE_ROOT}/${GBROWSE_VERSION}/tmp/persistent \
  		  --databases    ${GBROWSE_ROOT}/${GBROWSE_VERSION}/databases \
		  --installconf  n \
		  --installetc   n
  > ./Build installdeps   # Be sure to install all components of the Plack stack:

      Plack
      Plack::App::CGIBin
      Plack::App::WrapCGI
      Plack::Builder
      Plack::Middleware::ReverseProxy
      Plack::Middleware::Debug
      CGI::Emulate::PSGI
      CGI::Compile

  // Should you need to adjust any values, run
  > ./Build.PL reconfig
  > ./Build install

    Note: the curent installer script SHOULD NOT require a root
    password if using local paths like this example. When it asks if
    you want to restart Apache, select NO.  It's not relevant for us.
  
5. Fire up a Plack server using plackup.

   The Build script will have installed a suitable .psgi file at conf/GBrowse.psgi.

   Launch a simple plack HTTP server via:
   > plackup -p 9001 ${GBROWSE_ROOT}/${GBROWSE_VERSION}/conf/GBrowse.psgi

   Now open:
   http://localhost:9001/

   By default, plackup will use HTTP::Server::PSGI.


WHERE TO FROM HERE
---------------------------------------------

PSGI/Plack is really powerful. Here are some examples that take advantage 
of configuration already in the conf/GBrowse.psgi file.

Enable the Plack debugging middleware:

   > export GBROWSE_DEVELOPMENT=true
   > plackup -p 9001 ${GBROWSE_ROOT}/${GBROWSE_VERSION}/conf/GBrowse.psgi
   Visit http://localhost:9001/ and see all the handy debugging information.

   Or, directly from the command line.

Run GBrowse under the preforking, lightweight HTTP server Starman
   > perl -MCPAN -e 'install Starman'
   > starman -p 9001 ${GBROWSE_VERSION}/${GBROWSE_VERSION}/conf/GBrowse.psgi



AUTHOR
---------------------------------------------

Todd Harris (todd@wormbase.org)
11 Sep 2011