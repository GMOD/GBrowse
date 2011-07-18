package Bio::Graphics::Browser2::Render::SnapshotManager;

use strict;
use warnings;
use base 'Bio::Graphics::Browser2::Render::HTML';
use Bio::Graphics::Browser2::Shellwords;
use Bio::Graphics::Browser2::SubtrackTable;
use Bio::Graphics::Karyotype;
use Bio::Graphics::Browser2::Util qw[citation url_label segment_str];
use JSON;
use Digest::MD5 'md5_hex';
use Carp qw(croak cluck);
use CGI qw(:standard escape start_table end_table);
use Text::Tabs;
use POSIX qw(floor);

use constant JS    => '/gbrowse2/js';
use constant ANNOTATION_EDIT_ROWS => 25;
use constant ANNOTATION_EDIT_COLS => 100;
use constant MAXIMUM_EDITABLE_UPLOAD => 1_000_000; # bytes
use constant DEBUG => 0;

use constant HAVE_SVG => eval "require GD::SVG; 1";

sub render_saved_snapshots_listing{
 my $self = shift; 
 my $settings = $self->state;
 my $snapshots = $settings->{snapshots};
 my @snapshot_keys =  keys %$snapshots;
 my @sortedSnapshots = sort @snapshot_keys;
 my $imageURL;
 my $base;
 my $s;
 my $timeStamp;
 my $buttons = $self->data_source->globals->button_url;
 my $deleteSnapshotPath = "$buttons/snap_ex.png";
 my $setSnapshotPath    = "$buttons/snap_check.png";
 my $sendSnapshotPath	= "$buttons/snap_send.png";
 my $downSnapshotPath	= "$buttons/snap_down.png";
 my $mailSnapshotPath 	= "$buttons/snap_mail.png";
 my $nameHeading = $self->translate('SNAPSHOT_FORM');
 my $timeStampHeading = $self->translate('TIMESTAMP');
 my $escapedKey;

#  creating the snapshot banner with the load and upload sections
 my $html = div({-id => "Snapshot_banner",},
	    h2({-style => "position:relative;display: inline-block; margin-right: 1em;"}, $self->translate('SNAPSHOT_SELECT')),
	    input({-type => "button", -name => "LoadSnapshot", -value => "Load Snapshot", -onclick => '$(\'load_snapshot\').show()',}),
	    div(
		{-id	=>"load_snapshot",
		 -style	=> 'background-color:whiteSmoke; border-width:2px; border-style:solid; border-color:gray; position:absolute;left:200px; width:620px; z-index:1000000; display:none; padding:5px;'},  
			div(
				{-id => "load_snapshot_contents",
				 -style => 'color:black; font-family:sans-serif; font-size: 11pt; 				margin-top:5px;overflow-x: auto; overflow-y: auto;',},
					h1({-id => "load_snapshot_header",},"Load Snapshot"),
					p({-id => "load_snapshot_message",}, "Provide a name and insert the code for the snapshot to be loaded below:",
					  input({-type => "text", -id => "load_snapshot_name", -value =>"Snapshot Name", -style => 'margin:10px; margin-left:0px;', -onclick => 'this.value = \'\'',},),
					  textarea({-id => "load_snapshot_code", -style => 'width:605px; height:120px; padding:5px; border-color:gray;',},"",),),
					input({ -type => "button",
						-name => "Load",
						-value => "Load",
						-onclick => 'Controller.loadSnapshot()',}),
					input({ -type => "button",
						-name => "Cancel",
						-value => "Cancel",
						-onclick => '$(\'load_snapshot\').hide()',}),
							    ),
		),
	    start_form({-enctype => "multipart/form", -method=>"post", -action=>"gbrowse_upload.pl",}),	
	    	input({-type => "file", -name => "UpSnapshot", -value => "Upload Snapshot", -accept => "text/plain",}),
	    	input({-type => "submit", -name => "UploadSnapshot", -value => "Upload Snapshot",}),end_form(),	 	
		);

$html .= div({-id=>'headingRow',-style=>"height:30px;width:501px;background-color:#F0E68C"},
	 h1({-style => "position:relative; left:3em; margin-right: 1em; width:180px"},$nameHeading),
	 h1({-style => " position:relative; left:235px;bottom:30px;margin-right: 1em;"},$timeStampHeading),
	      );
$html.= qq(<div id = "snapshotTable">);
 for my $keys(@sortedSnapshots) { 
  if($keys){
    $timeStamp = $snapshots->{$keys}->{session_time};
    $imageURL = $snapshots->{$keys}->{image_url};
    ($base,$s) = $self->globals->gbrowse_base;
    $escapedKey = $keys;
    $escapedKey =~ s/(['"])/\\$1/g;
    warn "time = $timeStamp" if DEBUG;
# Creating the snapshots table with all the snapshot features
if($keys ne " " || ""){
 $html 	  .=  


	      div({ 
 		    -class=>"draggable",
		    -id=>$keys || 'snapshotname',
		    -style=> "padding-left:1em;width:485px;height:35px;border-style:solid;border-width:1px;border-color:#F0E68C; background-color:#FFF8DC; cursor: move;font-size:14px;position:relative;"},
		  span({-id=>"set_${keys}"},  img({   -src         => $setSnapshotPath, 
						      -id          => "set",
						      -onClick     =>  "Controller.setSnapshot('$escapedKey')",
						      -style       => 'cursor:pointer;margin-top:10px',
				
						  },
						    )
						      ),
		 span({-id=>"kill_${keys}"},  img({   -src         => $deleteSnapshotPath, 
						      -id          => "kill",
						      -onClick     =>  "Controller.killSnapshot('$escapedKey')",
						      -style       => 'cursor:pointer;margin-top:10px',
				
						  },
						    )
						      ),
		 span({-id=>"send_${keys}"},  img({   -src         => $sendSnapshotPath, 
						      -id          => "send",
						      -onClick     =>  "Controller.sendSnapshot('$escapedKey')",
						      -style       => 'cursor:pointer;margin-top:10px',
				
						  },
						    )
						      ),
		 span({-id=>"down_${keys}"},  img({   -src         => $downSnapshotPath, 
						      -id          => "down",
						      -onClick     => "Controller.downSnapshot('$escapedKey')",
						      -style       => 'cursor:pointer;margin-top:10px',
				
						  },
						    )
						      ),
		 span({-id=>"mail_${keys}"},  img({   -src         => $mailSnapshotPath, 
						      -id          => "mail",
						      -onClick     => '$(\'' . "mail_snapshot_${keys}" . '\').show()',
						      -style       => 'cursor:pointer;margin-top:10px',
				
						  },
						    )
						      ),

		 div(
			{-id	=>"send_snapshot_${keys}",
			 -class =>"send_snapshot",
			 -style	=> 'background-color:whiteSmoke; border-width:2px; border-style:solid; border-color:gray; position:absolute;left:200px; width:620px; z-index:1000000; display:none; padding:5px;'},  
			 div(
				{-id => "send_snapshot_contents",
				 -style       => 'color:black; font-family:sans-serif; font-size: 11pt; 				margin-top:5px;overflow-x: auto; overflow-y: auto;',},
				h1({-id => "snapshot_header_${keys}",},"Send Snapshot: ${keys}"),
				p({-id => "snapshot_message_${keys}",}, "To send this snapshot, use the following: ",),
				textarea({-id => "send_snapshot_url_${keys}", -style => 'width:605px; height:120px; padding:5px; border-color:gray;',},"",),
				input({ -type => "button",
					-name => "OK",
					-value => "OK",
					-onclick => '$(\'' . "send_snapshot_${keys}" . '\').hide(); this.style.zIndex = \'0\'',}),
						    ),
						      ),

		 div(
			{-id	=>"mail_snapshot_${keys}",
			 -class =>"mail_snapshot",
			 -style	=> 'background-color:whiteSmoke; border-width:2px; border-style:solid; border-color:gray; position:absolute;left:200px; width:420px; z-index:1000000; display:none; padding:5px;'},  
			 div(
				{-id => "mail_snapshot_contents",
				 -style       => 'color:black; font-family:sans-serif; font-size: 11pt; 				margin-top:5px;overflow-x: auto; overflow-y: auto;',},
				h1({-id => "mail_snap_header_${keys}",},"Mail Snapshot: ${keys}"),
				p({-id => "mail_snap_message_${keys}",}, "Enter the email of the person you wish to send the snapshot to: ",),
				input({-type => "text", -id => "email_${keys}", -style => 'width:280px; border-color:gray;',},"",),
				input({ -type => "button",
					-name => "Mail",
					-value => "Send",
					-onclick => "Controller.mailSnapshot('$escapedKey')",}),
				input({ -type => "button",
					-name => "Cancel",
					-value => "Cancel",
					-onclick => '$(\'' . "mail_snapshot_${keys}" . '\').hide(); this.style.zIndex = \'0\'',}),
						    ),
						      ),


		 span({-style=>"width:230px;"},
		 span({-class => "snapshot_names", -style=>"margin-top:10px; margin-left: 10px;"}, $keys)),
		 span({-class => "timestamps",-style=>"width:230px;position:absolute;left:235px;bottom:7px;margin-top:10px;font-size:14px"},$timeStamp,
				  img({-src => $imageURL, -width=>"50",-height=>"30", -style=>"position:absolute;left:180px;top:-8px;", 
-onmouseover => 'this.style.width=\'650px\'; this.style.height=\'auto\'; this.style.zIndex=\'1000\';',
-onmouseout => 'this.style.width=\'50px\'; this.style.height=\'30px\'; this.style.zIndex=\'0\';'},),) ),
		  
			   }

			      }
				     }

$html 	  .=  qq(</div>);
 return $html;
}
1;
