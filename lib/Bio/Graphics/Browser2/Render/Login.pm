package Bio::Graphics::Browser2::Render::Login;
use strict;
use warnings;

use Bio::Graphics::Browser2::Render;
use CGI qw(:standard);

sub new {
    my $class = shift;
    my $render = shift;
    return bless {renderer=>$render},ref $class || $class;
}

sub renderer {
    shift->{renderer};
}

sub destroy {
    delete shift->{renderer}; # avoid memory cycles
}

sub render_login {
    my $self   = shift;
    my $render = $self->renderer;

    $render->init_plugins;
    my $auth     =  $render->plugins->auth_plugin;
    if ($auth) {
	$self->render_plugin_login($auth);
    } else {
	$self->render_builtin_login;
    }
}

sub render_confirm {
    my $self   = shift;

    my $render = $self->renderer;
    my $output = '';

    if (param('confirm') && param('code')) {
	$output .= $self->render_account_confirm(param('code'));
    } 
    elsif (param('openid_confirm') && param('page') && param('s')) {
	$output .= $self->render_openid_confirm(param('page'),param('s'));
    }
    return $output;
}

# this is the contents of the plugin-generated login form
sub wrap_login_form {
    my $self = shift;
    my $plugin = shift;
    my $render     = $self->renderer;

    my $plugin_type  = $plugin->type;
    my $plugin_name  = $plugin->name;
    my $auth_hint    = $plugin->authentication_hint;
    my $auth_help    = $plugin->authentication_help;
    
    my $form = $plugin->configure_form;
    my $html = div(
	div({-id=>'login_message'},''),
	b($auth_hint ? $render->translate('LOGIN_REQUEST',"to $auth_hint")
	   	     : $render->translate('LOGIN_REQUEST','')),
	start_form({-name     => 'configure_plugin',
		   -id        => 'plugin_configure_form',
		   -onSubmit  => 'return false'}
	),
	$form,
	hidden(-name=>'plugin',-value=>$plugin_name),
	button(
	    -name    => $render->translate('Cancel'),
	    -onClick => 'Box.prototype.hideTooltip(true)'
	),
	button(
	    -name    => 'plugin_button',
	    -value   => $render->translate('LOGIN'),
	    -onClick => "Controller.plugin_authenticate(\$('plugin_configure_form'),\$('login_message'))",
	),
	checkbox(
	    -id      => 'authenticate_remember_me',
	    -name    => 'remember',
	    -label   => $render->translate('REMEMBER_ME')
	),
	end_form(),
	script({-type=>'text/javascript'},<<EOS )
Event.observe(\$('plugin_configure_form'),'keydown',
      function(e){ if (e.keyCode==Event.KEY_RETURN)
	      Controller.plugin_authenticate(\$('plugin_configure_form'),\$('login_message'))})
EOS
    );
    $html .= div($auth_help) if $auth_help;
    return $html;
}

sub render_plugin_login {
    my $self = shift;
    my $auth = shift;

    my $render   = $self->renderer;
    my $session  = $render->session;
    my $style    = $self->link_style;
    my $fullname = $render->userdb->fullname_from_sessionid($session->id);
    return span({-style=>$self->container_style},
		$session->private ? (
		    span({-style => 'font-weight:bold;color:black;'}, 
			 $render->translate('WELCOME', $fullname)),
		    span({-style => $style,
			 -onMouseDown => "location.href='?id=logout'"},
			 $render->translate('LOG_OUT', $fullname))
		)
		: (
		    span({-style       => $style,
			  -onMouseDown => "GBox.modalDialog(event,'url:?action=plugin_login',380)"
			 },
			 $render->translate('LOGIN'))
		)
	);
}

sub link_style {
    my $self = shift;
    return 'font-weight:bold;color:blue;cursor:pointer;';
}

sub container_style {
    my $self = shift;
    return 'float:right;padding-top:3px';
}

sub render_builtin_login {
    my $self = shift;

    my $render = $self->renderer;
    my $globals = $render->globals;
    
    my $images   = $globals->openid_url;
    my $appname  = $globals->application_name;
    my $appnamel = $globals->application_name_long;
    my $session  = $render->session;
    my $style    = $self->link_style;
    my $login_controls  = '';

	# Draw the visible HTML elements.
    if ($session->private) {
    	$login_controls .= span({-style => 'font-weight:bold;color:black;'}, 
				$render->translate('WELCOME', 
						   $render->userdb->fullname_from_sessionid($session->id)
						   || $session->username)
	    );
    	$login_controls .= '&nbsp; &nbsp;';
        $login_controls .= span({
	    -style 	   => $style,
	    -title 	   => $render->translate('CHANGE_SETTINGS_DESC'),
	    -onMouseDown => $self->login_globals.';'.$self->logout_dialogue,
	    -onMouseOver => 'this.style.textDecoration=\'underline\'',
	    -onMouseOut  => 'this.style.textDecoration=\'none\''}, $render->translate('MY_ACCOUNT'));
	$login_controls .= '&nbsp; &nbsp;';
        $login_controls .= span({
	    -style       => $style,
	    -title       => $render->translate('LOG_OUT_DESC', $session->username),
	    -onMouseDown => $self->login_globals.';'.'location.href=\'?id=logout\';',
	    -onMouseOver => 'this.style.textDecoration=\'underline\'',
	    -onMouseOut  => 'this.style.textDecoration=\'none\''}, 'Log Out');
    } else {
        $login_controls .= span({
	    -style	   => $style,
	    -title 	   => $render->translate('LOGIN_CREATE_DESC'),
	    -onMouseDown => $self->login_globals.';'.$self->login_dialogue,
	    -onMouseOver => 'this.style.textDecoration=\'underline\'',
	    -onMouseOut  => 'this.style.textDecoration=\'none\''},
				$render->translate('LOGIN_CREATE'));
    }
    my $container = span({-id=>'login_menu',-style => $self->container_style}, $login_controls);
    return $container;
}

sub login_script {
    my $self = shift;
    return join (';',$self->login_globals,$self->login_dialogue);
}

sub login_globals {
    my $self = shift;
    my $globals   = $self->renderer->globals;
    my $images    = $globals->openid_url;
    my $appname   = $globals->application_name;
    my $appnamel  = $globals->application_name_long;
    my $source    = $self->renderer->data_source->name;
    return "load_login_globals('$images','$appname','$appnamel','$source')";
}

sub login_dialogue {
    my $self = shift;
    my $render    = $self->renderer;
    my $sessionid = $render->session->id;
    return "load_login_balloon(event,'$sessionid',false,false)";
}

sub logout_dialogue {
    my $self = shift;
    my $render    = $self->renderer;
    my $session   = $render->session;
    my $sessionid = $session->id;
    my $username  = $session->username;
    my $openid    = $session->using_openid;
    return "load_login_balloon(event,'$sessionid','$username',$openid)";
}

sub render_account_confirm {
    my $self = shift;
    my $confirm = shift;
    my $render   = $self->renderer;
    my $settings = $render->state;
    my $login_globals = $self->login_globals;

    return $settings->{head} 
       ? iframe({-style  => 'display:none;',
		 -onLoad => "$login_globals;confirm_screen('$confirm')"
		}
	   )
        : "";
}

sub render_openid_confirm {
    my $self = shift;
    my ($page,$current_sessionid) = @_;

    my $render  = $self->renderer;
    my $globals = $render->globals;

    my $settings        = $render->state;
    my $session         = $render->session;
    my ($email,$gecos)  = $self->gecos_from_openid;

    my $logged_in      = $session->private ? 'true' : 'false';
    my $id             = $session->id;
    my $login_globals  = $self->login_globals;

    my $load      = "$login_globals;".
     	            "login_blackout(true,'');".
     		    "confirm_openid('$id','$page',$logged_in,'$email','$gecos');";
    return $settings->{head} ?
        iframe({-style  => 'display:none;',
                -onLoad => $load}
	)
        : "";
}

sub gecos_from_openid {
    my $self = shift;
    my $email = param('openid.ax.value.email')     || param('openid.ext1.value.email')     || '';
    my $first = param('openid.ax.value.firstname') || param('openid.ext1.value.firstname') || '';
    my $last  = param('openid.ax.value.lastname')  || param('openid.ext1.value.lastname') || '';
    my $gecos;
    # pull name out of email
    if ($email =~ /^\"([^\"]+)\"\s+([^@]+@[^@]+)$/) {
	$gecos = $1;
	$email = $2;
    } else {
	$gecos = $first || $last ? join(' ',$first,$last) : '';
    }
    return ($email,$gecos);
}

##########################################################33
## handle asynchronous requests
##
## this used to be done in gbrowse_login script
##########################################################33

sub run_asynchronous_request {
    my $self = shift;
    my $q    = shift;  # CGI object
    my $userdb = $self->renderer->userdb;
    $userdb or return (500,'text/plain',"Couldn't get userdb object");

    my %actions  = map {$_=>1} $q->param('login_action');
    my %callback;

    my $user       = $q->param('user');
    my $pass       = $q->param('pass');
    my $email      = $q->param('email');
    my $fullname   = $q->param('fullname');
    my $sessionid  = $q->param('session');
    my $remember   = $q->param('remember');
    
    my $old      = $q->param('old_val');
    my $new      = $q->param('new_val');
    my $column   = $q->param('column');
    
    my $confirm  = $q->param('confirm');
    my $openid   = $q->param('openid');
    my $option   = $q->param('option');
    my $source   = $q->param('source');

    my $can_register = $self->renderer->globals->user_accounts_allow_registration;
    my $can_openid   = $self->renderer->globals->user_accounts_allow_openid;

    my ($status,$content_type,$content) =
	  $actions{list_openid}       ? $userdb->do_list_openid($user)
	 :$actions{confirm_openid}    ? $can_openid &&
	                                $userdb->do_confirm_openid({$q->param('callback')},$sessionid, $option,$email,$fullname)
	 :$actions{validate}          ? $userdb->do_validate($user, $pass, $remember)
	 :$actions{add_user_check}    ? $userdb->do_add_user_check($user, $email, $fullname, $pass, $sessionid)
	 :$actions{add_user}          ? $can_register && 
	                                $userdb->do_add_user($user, $email, $fullname, $pass, $sessionid)
	 :$actions{edit_confirmation} ? $userdb->do_edit_confirmation($email, $option)
	 :$actions{confirm_account}   ? $can_register && 
	                                $userdb->do_confirm_account($user, $confirm)
	 :$actions{edit_details}      ? $userdb->do_edit_details($user, $column, $old, $new, $self->renderer->session)
	 :$actions{email_info}        ? $userdb->do_email_info($email)
	 :$actions{delete_user}       ? $userdb->do_delete_user($user, $pass)
	 :$actions{add_openid_user}   ? $can_openid &&
                                        $userdb->do_add_openid_user($user, $email,$fullname,$openid, $sessionid, $remember)
	 :$actions{check_openid}      ? $userdb->do_check_openid($openid, $sessionid, $source, $option)
	 :$actions{change_openid}     ? $can_openid &&
	                                $userdb->do_change_openid($user, $pass, $openid, $option)
	 :$actions{get_gecos}         ? $userdb->do_get_gecos($user)
	 :$actions{get_email}         ? $userdb->do_get_email($user)
	 :(500,'text/plain','programmer error');
    return ($status,$content_type,$content);
}

1;
