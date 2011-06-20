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
 my $source = $self->data_source->name;
 my $settings = $self->state;
 my $session = $self->session->session->{'_DATA'}->{$source};
 my $snapshots = $session->{snapshots};
 my @snapshot_keys =  keys %$snapshots;
 my @sortedSnapshots = sort @snapshot_keys;
 my $imageURL;
 my $base;
 my $s;
 my $timeStamp;
 my $buttons = $self->data_source->globals->button_url;
 my $deleteSnapshotPath = "$buttons/snap_trash.png";
 #my $setSnapshotPath    = "$buttons/snap_check.png";
 my $sendSnapshotPath	= "$buttons/snap_share.png";
 my $mailSnapshotPath 	= "$buttons/snap_mail.png";
 my $closeImage 	= "$buttons/ex.png";
 my $nameHeading = $self->translate('SNAPSHOT_FORM');
 my $timeStampHeading = $self->translate('TIMESTAMP');
 my $url = $self->globals->gbrowse_url();
 my $escapedKey;

#  creating the snapshot banner
 my $html = div({-id => "Snapshot_banner",},
	    h1({-style => "position:relative;display: inline-block; margin-right: 1em;"}, $self->translate('SNAPSHOT_SELECT')),
	    input({-type => "button", -name => "Save Snapshot", -value => "Save Snapshot", -onClick => '$(\'save_snapshot_2\').show(); $(\'snapshot_name_2\').select();',}),
	    div({-id => 'save_snapshot_2',-style => "width:184px;height:50px;background:whitesmoke;z-index:1; border:2px solid gray;display:none; padding: 5px; position: fixed; left: 140px; z-index: 1000000;"},
				div({
				    -id=>'snapshot_form_2',},
				    input({
					    -type => "text",
					    -name => "snapshot_name",
					    -id => "snapshot_name_2",
					    -style => "width:180px;",
					    -maxlength => "50",
					    -value =>  $self->translate('SNAPSHOT_FORM'), 	 
					    -onDblclick => "this.value='';"
					}),
				input({ -type => "button",
					-name => "Save",
					-value => "Save",
					-onclick => '$(\'save_snapshot_2\').hide(); this.style.zIndex = \'0\'; Controller.saveSnapshot(true);',
					-style => 'margin-left:35px;',}),
				input({ -type => "button",
					-name => "Cancel",
					-value => "Cancel",
					-onclick => '$(\'save_snapshot_2\').hide(); this.style.zIndex = \'0\'',}),
						    ),),
	    div({-id => "enlarge_image",
	          -style => 'display: none; position:absolute; left: 155px; top:100px; width: 1000px; border: #F0E68C; z-index: 10000;'},
		  img({-style => 'cursor:pointer;', -onclick=> '$(\'enlarge_image\').hide(); Box.prototype.greyout(false);', -src => "$closeImage"},),
	          img({-id => 'large_snapshot', -src => '', -width=>'1000', -height => 'auto'},),),
	    );

$html .= div({-id=>'headingRow',-style=>"height:20px;background-color:#F0E68C"},
	 h1({-style => "position:relative; left:100px; margin-right: 1em; width:180px"},$nameHeading),
	 h1({-style => " position:relative; left:550px;bottom:30px;margin-right: 1em; width: 300px;"},$timeStampHeading),
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
		    -style=> "padding-left:1em;height:35px;border-style:solid;border-width:1px;border-color:#F0E68C; background-color:#FFF8DC; cursor: move;font-size:14px;position:relative;",},
		  span({-id=>"set_${keys}"},  input({ -type        => "button", 
						      -class 	   => "snapshot_button",
						      -name        => "set",
						      -value 	   => "Load", 		
						      -onClick     =>  "Controller.setSnapshot('$escapedKey')",
						      -style       => 'cursor:pointer;margin-top:10px;',
						  },
						    )
						      ),
		 span({-id=>"kill_${keys}"},  img({   -src         => $deleteSnapshotPath, 
						      -id          => "kill",
						      -onClick     =>  "Controller.killSnapshot('$escapedKey')",
						      -style       => 'cursor:pointer;margin-top:10px',
						      -title 	   => 'Delete',		
						      -class 	   => 'snapshot_icon',		
						  },
						    )
						      ),
		 span({-id=>"send_${keys}"},  img({   -src         => $sendSnapshotPath, 
						      -id          => "send",
						      -onClick     =>  "Controller.sendSnapshot('$escapedKey')",
						      -style       => 'cursor:pointer;margin-top:10px',
						      -title 	   => 'Share',	
						      -class 	   => 'snapshot_icon',			
						  },
						    )
						      ),
		 span({-id=>"mail_${keys}"},  img({   -src         => $mailSnapshotPath, 
						      -id          => "mail",
						      -onClick     => '$(\'' . "mail_snapshot_$escapedKey" . '\').show();' 
								  	. "Controller.pushForward('$escapedKey')",
						      -style       => 'cursor:pointer;margin-top:10px',
						      -title 	   => 'Email',	
						      -class 	   => 'snapshot_icon',
						  },
						    )
						      ),

		 div(
			{-id	=>"send_snapshot_$escapedKey",
			 -class =>"send_snapshot",
			 -style	=> 'background-color:whiteSmoke; border-width:2px; border-style:solid; border-color:gray; position:absolute;left:200px; width:800px; z-index:1000000; display:none; padding:5px;'},  
			 div(
				{-id => "send_snapshot_contents",
				 -style       => 'color:black; font-family:sans-serif; font-size: 11pt; 				margin-top:5px;overflow-x: auto; overflow-y: auto;',},
				div({-style => "border-bottom-style: solid; border-width: 1px; padding-left: 3px; width: 795px;"},
					b({-id => "snapshot_header_$escapedKey",},"Send Snapshot: " . (substr $escapedKey, 5) . ""),),
				p({-id => "snapshot_message_$escapedKey", -style => "font-size: small;",}, "To open this snapshot, use the following link: ",),
				textarea({-id => "send_snapshot_url_$escapedKey", -style => 'width:785px; padding:5px; border-color:gray;',},"",),
				input({ -type => "button",
					-name => "OK",
					-value => "OK",
					-onclick => '$(\'' . "send_snapshot_$escapedKey" . '\').hide(); this.style.zIndex = \'0\'',}),
						    ),
						      ),

		 div(
			{-id	=>"mail_snapshot_$escapedKey",
			 -class =>"mail_snapshot",
			 -style	=> 'background-color:whiteSmoke; border-width:2px; border-style:solid; border-color:gray; position:absolute;left:200px; width:420px; z-index:1000000; display:none; padding:5px;'},  
			 div(
				{-id => "mail_snapshot_contents",
				 -style       => 'color:black; font-family:sans-serif; font-size: 11pt; 				margin-top:5px;overflow-x: auto; overflow-y: auto;',},
				div({-style => "border-bottom-style: solid; border-width: 1px; padding-left: 3px; width: 415px;"},
					b({-id => "mail_snap_header_$escapedKey",},"Mail Snapshot: " . (substr $escapedKey, 5) . ""),),	
				p({-id => "mail_snap_message_$escapedKey", -style => "font-size: small;",}, "Enter the email of the person you wish to send the snapshot to: ",),
				input({-type => "text", -id => "email_$escapedKey", -style => 'width:280px;',},"",),
				input({ -type => "button",
					-name => "Mail",
					-value => "Send",
					-onclick => "Controller.mailSnapshot('$escapedKey')",}),
				input({ -type => "button",
					-name => "Cancel",
					-value => "Cancel",
					-onclick => '$(\'' . "mail_snapshot_$escapedKey" . '\').hide(); this.style.zIndex = \'0\'',}),
						    ),
						      ),

		 span({-style=>"width:230px;"},
		 span({-class => "snapshot_names", -style=>"margin-top:10px; margin-left: 10px;"}, (substr $escapedKey, 5))),
		 span({-class => "timestamps",-style=>"width:230px;position:absolute;left:550px;bottom:7px;margin-top:10px;font-size:14px"},$timeStamp,
				  img({-src => $imageURL, -width=>"50",-height=>"30", -style=>"position:absolute;left:180px;top:-8px;cursor:pointer;border: solid 1px black;", 
-onclick => 'Controller.enlarge_image(' . "'${imageURL}'" . '); $(' . "'$escapedKey'" . ').style.zIndex = \'0\';',
-onmouseover => 'this.style.width=\'550px\'; this.style.height=\'auto\';' . "Controller.pushForward('$escapedKey');" . 'this.style.zIndex=\'1000\';',
-onmouseout => 'this.style.width=\'50px\'; this.style.height=\'30px\'; this.style.zIndex=\'0\';'},),), ),		  
			   }

			      }
				     }

$html 	  .=  qq(</div>);
 return $html;
}
1;
