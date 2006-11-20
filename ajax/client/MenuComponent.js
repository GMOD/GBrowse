/* -----------------------------------------------
 
 Feature pop up menu
 Mainly Sylvain Gaillard and Gaëtan Droc's original code
 with some changes by SMcGowan and S Taylor
 Computational Biology Research Group, Oxford 
 
------------------------------------------------*/

// GLOBALS

var title_bg = "#EFBA56";
var title_fg = "#000000";
var table_border = "#000000";
var table_bg = "#D8DEC7";
var table_fg = "#000000";
var table_width = 250;
var timein = 1700; // time to wait on the link before the window appear and to wait after leaving window to make it disapear (in milliseconds)
var timeout = 2500; // time to wait before destroying the window if you never inter it (in milliseconds)
var close_btn = "close.png"
var x_offset = 5;
var y_offset = 5;

var x_pos;
var y_pos;
var draw_win;
var hide_win;



// function MenuComponent_to get the mouse position
function MenuComponent_getMouse(e) { 
	x_pos = (!document.all) ? e.pageX : event.x+document.body.scrollLeft;
	// Adjust x_pos to prevent pop-up menu being displayed beyond right edge of window:
	if (window.innerWidth) {
		theWidth = window.innerWidth
		theHeight = window.innerHeight
	}
	else if (document.documentElement && document.documentElement.clientWidth) {
		theWidth = document.documentElement.clientWidth
		theHeight = document.documentElement.clientHeight
	}
	else if (document.body) {
		theWidth = document.body.clientWidth
		theHeight = document.body.clientHeight
	}
	if (x_pos > ((theWidth+document.body.scrollLeft)-260)){
		x_pos = (!document.all) ? (e.pageX-265) : ((theWidth+document.body.scrollLeft)-265);
	}	
	if (!document.all) { y_pos = e.pageY }
	else {
		if (document.documentElement && document.documentElement.scrollTop) { 
			y_pos = event.y + document.documentElement.scrollTop; }
		else if (document.body) { y_pos = event.y + document.body.scrollTop; }
		else { y_pos = event.y + window.pageYOffset; }
	}
//			alert(y_pos+' | '+document.documentElement.scrollTop+' | '+document.body.scrollTop+' | '+window.pageYOffset)
	
}

if (document.getElementById) {
	if(navigator.appName.substring(0,3) == "Net")
		document.captureEvents(Event.MOUSEMOVE);
		document.onmousemove = MenuComponent_getMouse;
}


// Timout before drawing window
function MenuComponent_showDescription(title,msg) {
	draw_win = setTimeout("MenuComponent_drawWindow(\""+title+"\",\""+msg+"\")", timein);
}

// function MenuComponent_to build the window and drawing it
function MenuComponent_drawWindow(title,msg) {
	MenuComponent_outWindow(timeout);
	var window_timer = " onmouseover=\"MenuComponent_onWindow();\" onmouseout=\"MenuComponent_outWindow(timein);\"";
	var description = "";
	description += "<table border=\"0\" cellpadding=\"0\" cellspacing=\"0\" bgcolor=\"" + table_border + "\""+window_timer+">";
	description += 	"<tr>";
	description += 		"<td>";
	description += 			"<table width=\"100%\" border=\"0\" cellpadding=\"0\" cellspacing=\"1\""+window_timer+">";
	description += 				"<tr>";
	description += 					"<td class=\"menuTitle\""+window_timer+">";
	description += 						title;
	description += 					"</td>";
	description += 					"<td class=\"menuButton\" width=\"11px\""+window_timer+">";
	description += 						"<img src=\""+close_btn+"\" alt=\"close\" onclick=\"MenuComponent_hideDescription();\" />";
	description += 					"</td>";
	description += 				"</tr>";
	description += 				"<tr>";
	description +=					"<td colspan=\"2\" class=\"menuDisplay\""+window_timer+">";
	description += 						msg;
	description += 					"</td>";
	description += 				"</tr>";
	description += 			"</table>";
	description += 		"</td>";
	description += 	"</tr>";
	description += "</table>";
	if (document.getElementById) {
		document.getElementById("description").style.top = y_pos+y_offset+"px";
		document.getElementById("description").style.left = x_pos+x_offset+"px"; 
		document.getElementById("description").innerHTML = description;
		document.getElementById("description").style.visibility = "visible";
	}
}

// Stop the timeout if living before it ends
function MenuComponent_outLink() {
	clearTimeout(draw_win);
}

// Destroy the window
function MenuComponent_hideDescription() {
	if (document.getElementById) {
		document.getElementById("description").style.visibility = "hidden";
	}
}

function MenuComponent_onWindow() {
	clearTimeout(hide_win);
}

function MenuComponent_outWindow(time) {
	clearTimeout(hide_win);
	hide_win = setTimeout("MenuComponent_hideDescription()",time);
}

