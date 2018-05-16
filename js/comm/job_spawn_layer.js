var JSL_VARS = {
    "TOTAL_JOBS_SPAWNED" : 0
};

// Get the sys args from the url. These must come at the end of the url, having the format ?args= JSON string list of args.
function pcl_jsapi_get_sysargs() {
    var jobname = pcl_jsapi_get_job_name();

    var href = decodeURIComponent(document.location.href);
    console.log(href);
    var idx = href.indexOf("?args=");
    if (idx < 0)
        return [jobname];
    try {
        var ret = JSON.parse(href.substr(idx + "?args=".length));
        if (Array.isArray(ret)) {
            ret.unshift(jobname);
            return ret;
        } else {
            return [jobname, ret];
        }
    } catch (_) {
        console.log("WARN: args are not formatted correctly!");
        return [jobname];
    }
}

// Get the job name of the current script, based on the url of the current script.
function pcl_jsapi_get_job_name() {
    try {
        return document.getElementById("actor_job_name").innerText;
    } catch (e) {
        console.log("CANNOT GET THE JOB NAME! Must tag the script of the job in the html file with id 'actor_job_name'");
        throw e; // pass it forward
    }
}

function pcl_jsapi_spawn_job_with_args(job_name, args) {
    var args = encodeURIComponent(JSON.stringify(args));

    var new_pathname = window.location.pathname.split('/').slice(0, -1).join("/");
    var newURL = window.location.protocol + "//" + window.location.host + "/" + new_pathname + "/" + job_name + ".html";
    newURL += "?args=" + args;

    JSL_VARS.TOTAL_JOBS_SPAWNED += 1;

    return add_new_job_button(JSL_VARS.TOTAL_JOBS_SPAWNED, newURL);
}

/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ {HTMLutils ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ {HTMLutils ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ {HTMLutils ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/

// Opens a new page.
function open_new_page(job_id, newUrl) {
    $(document).ready(function () {
        var OpenWindow = window.open(newUrl, "spawned_job_" + job_id, '');
    });
}

// Adds a button to start a new job!.
function add_new_job_button(job_id, newUrl) {
    $(document).ready(function () {
        var button_div_class = 'new_job_button_' + job_id;
        var button_id = 'button_for_job_' + job_id;

        var $button_div = $('<div id="' + button_div_class + '"></div>');
        $('<p>New job available with id: ' + job_id + '</p>').appendTo($button_div);
        var $start_button = $('<input type="button" id="' + button_id + '" value="Click to start!"/></div>');

        $("body").on("click", ("#" + button_div_class + " #" + button_id), function () {
            open_new_page(job_id, newUrl);
            $("#" + button_div_class).remove();
        });

        $start_button.appendTo($button_div);
        $button_div.appendTo($("body"));
    });
}

/** ----------------------------------------------------------- {HTMLutils ------------------------------- */
/** ----------------------------------------------------------- {HTMLutils ------------------------------- */
/** ----------------------------------------------------------- {HTMLutils ------------------------------- */

function __test_stuff() {
    console.log('Job name:', pcl_jsapi_get_job_name());
    console.log('Command line args:', pcl_jsapi_get_sysargs());
    pcl_jsapi_spawn_job_with_args("new_job1", ["abc", "2333b"]);
    pcl_jsapi_spawn_job_with_args("new_job2", ["xyz", "2333b"]);
}