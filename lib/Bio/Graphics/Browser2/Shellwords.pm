package Bio::Graphics::Browser2::Shellwords;

require Text::ParseWords;

use base 'Exporter';
our @EXPORT = 'shellwords';


sub shellwords {
  return unless @_;
  return Text::ParseWords::shellwords(@_);
}

1;


