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
    } elsif (param('openid_confirm') && param('page') && param('s')) {
	$output .= $self->render_openid_confirm(param('page'),param('s'));
    }
    return $output;
}


sub render_plugin_login {
    my $self = shift;
    my $auth = shift;

    my $render   = $self->renderer;
    my $session  = $render->session;
    my $style    = $self->link_style;
    return span({-style=>$self->container_style},
		$session->private ? (
		    span({-style => 'font-weight:bold;color:black;'}, 
			 $render->translate('WELCOME', $session->username)),
		    span({-style => $style},
			 $render->translate('LOG_OUT', $session->username))
		)
		: (
		    span({-style       => $style,
			  -onMouseDown => "GBox.showTooltip(event,'url:?action=plugin_login',true)"
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
	    -title 	   => $render->translate('LOG_OUT_DESC', $session->username).'',
	    -onMouseDown => 'load_login_globals(\''.$images.'\',\''.$appname.'\',\''.$appnamel.'\'); load_login_balloon(event,\''.$session->id.'\',\''.$session->username.'\','.$session->using_openid.');',
	    -onMouseOver => 'this.style.textDecoration=\'underline\'',
	    -onMouseOut  => 'this.style.textDecoration=\'none\''}, $render->translate('MY_ACCOUNT'));
	$login_controls .= '&nbsp; &nbsp;';
        $login_controls .= span({
	    -style       => $style,
	    -title       => $render->translate('CHANGE_SETTINGS_DESC'),
	    -onMouseDown => 'load_login_globals(\''.$images.'\',\''.$appname.'\',\''.$appnamel.'\'); location.href=\'?id=logout\';',
	    -onMouseOver => 'this.style.textDecoration=\'underline\'',
	    -onMouseOut  => 'this.style.textDecoration=\'none\''}, 'Log Out');
    } else {
        $login_controls .= span({
	    -style	   => $style,
	    -title 	   => $render->translate('LOGIN_CREATE_DESC'),
	    -onMouseDown => 'load_login_globals(\''.$images.'\',\''.$appname.'\',\''.$appnamel.'\'); load_login_balloon(event,\''.$session->id.'\',false,false);',
	    -onMouseOver => 'this.style.textDecoration=\'underline\'',
	    -onMouseOut  => 'this.style.textDecoration=\'none\''},
				$render->translate('LOGIN_CREATE'));
    }
    my $container = span({-style => $self->container_style}, $login_controls);
    return $container;
}

sub render_account_confirm {
    my $self = shift;
    my $confirm = shift;

    my $render  = $self->renderer;
    my $globals = $render->globals;

    my $images   = $globals->openid_url;
    my $appname  = $globals->application_name;
    my $appnamel = $globals->application_name_long;
    my $settings = $render->state;

    return $settings->{head} ?
        iframe({-style  => 'display:none;',
                -onLoad => 'load_login_globals(\''.$images.'\',\''.$appname.'\',\''.$appnamel.'\');
                 confirm_screen(\''.$confirm.'\')'})
        : "";
}

sub render_openid_confirm {
    my $self = shift;
    my ($page,$sesson) = @_;

    my $render  = $self->renderer;
    my $globals = $render->globals;

    my $images          = $globals->openid_url;
    my $appname         = $globals->application_name;
    my $appnamel        = $globals->application_name_long;
    my $settings        = $render->state;
    my $session         = $render->session;
    warn "render_openid_confirm()";
    warn 'param=',join ' ',param();
    my ($email,$gecos) = $self->gecos_from_openid;

    my $logged_in = $session->private ? 'true' : 'false';
    my $id        = $session->id;
    my $load      = "load_login_globals('$images','$appname','$appnamel');".
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
    warn "email=$email, first=$first, last=$last";
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



1;
