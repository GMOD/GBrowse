libraries: build_libraries

gbrowse: build_gbrowse

docs: build_docs

build_libraries:
	sudo scripts/build-libraries.pl

build_gbrowse:
	sudo scripts/build-gbrowse.pl

build_docs:
	pod2html --infile README.pod --outfile README.html
	rm -rf pod2htm*

