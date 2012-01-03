package Bio::Graphics::Browser2::Render::SnapshotManager;

use strict;
use warnings;
use Carp qw(croak cluck);
use CGI qw(:standard escape start_table end_table);

use constant JS    => '/gbrowse2/js';
use constant ANNOTATION_EDIT_ROWS => 25;
use constant ANNOTATION_EDIT_COLS => 100;
use constant MAXIMUM_EDITABLE_UPLOAD => 1_000_000; # bytes
use constant DEBUG => 0;

use constant HAVE_SVG => eval "require GD::SVG; 1";

sub new {
    my $class  = shift;
    my $render =  shift;
    return bless {render=>$render}, $class;
}

sub render { shift->{render} }

sub render_snapshots_listing {
    my $self      = shift; 
    my $render    = shift || $self->render;
    my $source    = $render->data_source->name;
    my $settings  = $render->state;
    my $snapshots = $render->session->snapshots;
    my @snapshot_keys   = keys %$snapshots;
    my @sortedSnapshots = sort @snapshot_keys;

    my ($imageURL,$base,$s,$timeStamp,$escapedKey);

    my $buttons            = $render->data_source->globals->button_url;
    my $deleteSnapshotPath = "$buttons/snap_trash.png";
    my $sendSnapshotPath	= "$buttons/snap_share.png";
    my $mailSnapshotPath 	= "$buttons/snap_mail.png";
    my $closeImage 	   = "$buttons/ex.png";
    my $nameHeading        = $render->translate('SNAPSHOT_FORM');
    my $timeStampHeading   = $render->translate('TIMESTAMP');
    my $url                = $render->globals->gbrowse_url();

#  creating the snapshot banner
    my $html = div({-id => "Snapshot_banner",},
		   h1({-id=>'snapshot_section_title'},$render->translate('SNAPSHOT_SELECT')),
		   input({-type => "button", -name => "Save Snapshot", -value => "Save Snapshot", 
			  -onClick => '$(\'save_snapshot_2\').show(); $(\'snapshot_name_2\').select();',}),
		   div({-id => 'save_snapshot_2',
			-style=>'display:none',
		       },
		       div({
			   -id=>'snapshot_form_2',},
			   input({
			       -type => "text",
			       -name => "snapshot_name",
			       -id => "snapshot_name_2",
			       -style => "width:180px;",
			       -maxlength => "50",
			       -value =>  $render->translate('SNAPSHOT_FORM'), 	 
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
		       )),
		   div({-id => "enlarge_image",
		       -style => 'display:none',
		       },
		       img({-id    => 'large_snapshot_close', 
			    -onclick=> '$(\'enlarge_image\').hide(); Box.prototype.greyout(false);', -src => "$closeImage"},),
		       img({-id => 'large_snapshot',       -width=>'1000', -height => 'auto'})
		   )
	);

    $html .= div({-id=>'headingRow',-style=>"height:20px;background-color:#F0E68C"},
		 h1({-style => "left:100px;width:180px"},$nameHeading),
		 h1({-style => "left:550px;width:300px;bottom:30px"},$timeStampHeading),
	);

    my $innerHTML = '';
    for my $snapshot_name (@sortedSnapshots) { 
	next unless $snapshot_name && $snapshot_name =~ /\S/;

	$timeStamp  = $snapshots->{$snapshot_name}{session_time};
	$imageURL   = $snapshots->{$snapshot_name}{data}{image_url};
	($base,$s)  = $render->globals->gbrowse_base;
	($escapedKey = $snapshot_name) =~ s/(['"])/\\$1/g;
	my $readable_name = CGI::unescape($snapshot_name);  # ugly, but easier to fix here than where the real bug is 
	 
	warn "time = $timeStamp" if DEBUG;
	
	# Creating the snapshots table with all the snapshot features
	my $set_snapshot = span({-id=>"set_$snapshot_name"},  input({ -type        => "button", 
								      -class 	   => "snapshot_button",
								      -name        => "set",
								      -value 	   => "Load", 		
								      -onClick     =>  "Controller.setSnapshot('$escapedKey')",
								    }));
	my $delete_snapshot = span({-id=>"kill_$snapshot_name"},  img({   -src         => $deleteSnapshotPath, 
									  -id          => "kill",
									  -onClick     =>  "Controller.killSnapshot('$escapedKey')",
									  -title 	   => 'Delete',		
									  -class 	   => 'snapshot_icon',		
								      }));
	my $send_snapshot = span({-id=>"send_$snapshot_name"},  img({   -src         => $sendSnapshotPath, 
									-id          => "send",
									-onClick     =>  "Controller.sendSnapshot('$escapedKey')",
									-title 	     => 'Share',	
									-class 	     => 'snapshot_icon',			
								    }));

	my $mail_snapshot = $self->render->globals->smtp_enabled ? (
	    span({-id=>"mail_$snapshot_name"},  img({   -src         => $mailSnapshotPath, 
							-id          => "mail",
							-onClick     => "\$('mail_snapshot_$escapedKey').style.display='block';" 
							                 . "Controller.pushForward('$escapedKey')",
							    -title 	   => 'Email',	
							    -class 	   => 'snapshot_icon',
						    })))
	    : '';
	
	my $send_snapshot_dialog = div({-id	=>"send_snapshot_$escapedKey",
					-class  =>"send_snapshot",
					-style  => 'display:none',
				       },

				       div({-id => "send_snapshot_contents"},
					   div({-id=>'send_snapshot_box'},
					       b({-id => "snapshot_header_$escapedKey",},"Send Snapshot: " . (substr $escapedKey, 5) . ""),),

					   p({-id => "snapshot_message_$escapedKey", 
					      -class=>'snapshot_message'},"To reload this snapshot at any time, use the following link: "),

					   textarea({-id => "send_snapshot_url_$escapedKey", -class=>'snapshot_url'},""),
					   input({ -type => "button",
						   -name => "OK",
						   -value => "OK",
						   -onclick => '$(\'' . "send_snapshot_$escapedKey" . '\').hide(); this.style.zIndex = \'0\'',}),
				       ));
    
	my $mail_snapshot_dialog = div({-id	=>"mail_snapshot_$escapedKey",
					-class =>"mail_snapshot"},  
				       div(
					   {-id => "mail_snapshot_contents"},
					   div({-class=>'mail_snapshot_box'},
					       b({-id => "mail_snap_header_$escapedKey",},"Mail Snapshot: " . (substr $escapedKey, 5) . ""),),	
					   p({-id => "mail_snap_message_$escapedKey", -style => "font-size: small;"},
					     "Enter the email of the person you wish to send the snapshot to: ",),
					   input({-type => "text", -id => "email_$escapedKey", -style => 'width:280px;',},"",),
					   input({ -type => "button",
						   -name => "Mail",
						   -value => "Send",
						   -onclick => "Controller.mailSnapshot('$escapedKey')",}),
					   input({ -type => "button",
						   -name => "Cancel",
						   -value => "Cancel",
						   -onclick => '$(\'' . "mail_snapshot_$escapedKey" . '\').hide(); this.style.zIndex = \'0\'',}),
				       ));
	my $snapshot_image = span({-class=>'snapshot_image_frame'},span({-class => "snapshot_names"}, (substr $readable_name, 5))).
				  span({-class => "timestamps"},$timeStamp,
					img({-src => $imageURL, -width=>"50",-height=>"30",-class=>'snapshot_image',
					     -onclick => 'Controller.enlarge_image(' . "'${imageURL}'" . '); $(' . "'$escapedKey'" . ').style.zIndex = \'0\';',
					     -onmouseover => "this.style.width='550px'; this.style.height='auto';Controller.pushForward('$escapedKey');this.style.zIndex='1000'",
					     -onmouseout  => "this.style.width='50px';  this.style.height='30px';this.style.zIndex='0'"}));
	
	 
	$innerHTML .= 
	    div({ 
		-class=>"draggable snapshot_table_entry",
		-id=>$snapshot_name || 'snapshotname'},
		$set_snapshot,
		$delete_snapshot,
		$send_snapshot,
		$mail_snapshot,
		$send_snapshot_dialog,
		$mail_snapshot_dialog,
		$snapshot_image);
    }
    $html .= div({-id=>'snapshotTable'},$innerHTML);
    return $html;
}

# *** Function to render the snapshot title.
sub render_title {
    my $self  = shift;
    my $render = $self->render;
    my $currentSnapshot = $render->translate('CURRENT_SNAPSHOT');
    my $settings = $render->state;

  if ($settings->{snapshot_active}){
      return h1({-id=>'snapshot_page_title',-class=>'normal'},"");
  } else {
      return h1({-id=>'snapshot_page_title',-class=>'normal', -style=>'display: none;'},"");}
}

sub snapshot_form {
    my $self = shift;
    # %% Adding form %%
    return div({
	-id=>'snapshot_form',},
	input({-type => "text",
	       -name => "snapshot_name",
	       -id => "snapshot_name",
	       -style => "width:180px",
	       -maxlength => "50",
	       -value =>  $self->render->translate('SNAPSHOT_FORM'), 	 
	       -onDblclick => "this.value='';",
	      })
	);
}

# *** Render select snapshots. ****
sub render_snapshots_section {
    my $self = shift;
    my $render = $self->render;
    my $userdata = $render->user_tracks;
    my $html = $render->is_admin ? h2({-style=>'font-style:italic;background-color:yellow'}, 
				   $render->translate('ADMIN_MODE_WARNING')) 
	                       : "";
    $html .= div({-id => "snapshots_page"}, $self->render_snapshots_listing());
    return div({-style => 'margin: 1em;'}, $html);
}

# *** Render the save session button ***
sub render_select_saveSession {
    my $self = shift;
    my $title = $self->render->translate('SAVE_SNAPSHOT');
    return button({-name=>$title,
		   -onClick => '$(\'save_snapshot\').show(); $(\'snapshot_name\').select();',
		  },	   
	);
}

sub render_select_loadSession {
    my $self = shift;
    my $title = $self->render->translate('LOAD_SNAPSHOT');
    return button({-name=>$title,
		   -onClick => "Controller.select_tab('snapshots_page');",
		  },	   
	);
}

sub snapshot_options {
    my $self = shift;
    my $snapshot_form = div({-id=>'snapshot_form'},$self->snapshot_form());
    my $saveSessionButton    = span({-id=>'unsessionbutton'},$self->render_select_saveSession());
    my $restoreSessionButton = span({-id=>'loadbutton'},     $self->render_select_loadSession());
    my $saveSessionStyle = "position:fixed;left;width:184px;height:50px;background:whitesmoke;z-index:1; border:2px solid gray;display:none; padding: 5px;";
    my $save_prompt = div({-id => 'save_snapshot',-style=>"$saveSessionStyle"},
			  $snapshot_form,
			  input({ -type => "button",
				  -name => "Save",
				  -value => "Save",
				  -onclick => '$(\'save_snapshot\').hide(); this.style.zIndex = \'0\'; Controller.saveSnapshot();'}),
			  input({ -type => "button",
				  -name => "Cancel",
				  -value => "Cancel",
				  -onclick => '$(\'save_snapshot\').hide(); this.style.zIndex = \'0\'',}),
	),;
    
    return div({-id => 'snapshot_options'},$saveSessionButton . $save_prompt . $restoreSessionButton);
}

1;
