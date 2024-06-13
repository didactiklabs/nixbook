{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
  copyqCommandsConfig = ''
    [Commands]
    1\Command="/*
    This adds support for KDE, Gnome, Sway and Hyprland Wayland sessions.

    For Sway and Hyprland, this requires:
    - `ydotool` utility to send copy/paste shortcuts to applications
    - `grim` for taking screenshot
    - `slurp` for selecting screenshot area

    For KDE, this requires Spectacle for taking screenshots.

    Getting current window title is not supported in KDE.

    Global shortcut commands can be triggered with:

        copyq triggerGlobalShortcut {COMMAND_NAME}

    On Gnome, clipboard monitor is executed as X11 app using XWayland.

    Links:
    - https://github.com/ReimuNotMoe/ydotool
    - https://github.com/emersion/grim
    - https://github.com/emersion/slurp
    */

    function isSway() {
        return env('SWAYSOCK').length != 0
    }

    function isHyprland() {
        return env('HYPRLAND_CMD').length != 0
    }

    function isGnome() {
        return str(env('XAUTHORITY')).includes('mutter-Xwayland')
    }

    function run() {
        var p = execute.apply(this, arguments)
        if (!p) {
            throw 'Failed to start ' + arguments[0]
        }
        if (p.exit_code !== 0) {
            throw 'Failed command ' + arguments[0] + ': ' + str(p.stderr)
        }
        return p.stdout
    }

    function swayGetTree() {
        var tree = run('swaymsg', '--raw', '--type', 'get_tree')
        return JSON.parse(str(tree))
    }

    function swayFindFocused(tree) {
        var nodes = tree['nodes'].concat(tree['floating_nodes'])
        for (var i in nodes) {
            var node = nodes[i]
            if (node['focused'])
                return node
            var focusedNode = swayFindFocused(node)
            if (focusedNode)
                return focusedNode
        }
        return undefined
    }

    function hyprlandFindFocused() {
        var window = run('hyprctl', '-j', 'activewindow')
        return JSON.parse(str(window))
    }

    function sendShortcut(...shortcut) {
        sleep(100)
        run('ydotool', 'key', ...shortcut)
    }

    global.currentWindowTitle = function() {
        if (isSway()) {
            var tree = swayGetTree()
            var focusedNode = swayFindFocused(tree)
            return focusedNode ? focusedNode['name'] : \'\'
        } else if (isHyprland()) {
            var focusedWindow = hyprlandFindFocused()
            return focusedWindow ? focusedWindow['title'] : \'\'
        }
        return \'\'
    }

    global.paste = function() {
        sendShortcut('42:1', '110:1', '110:0', '42:0')
    }

    var copy_ = global.copy
    global.copy = function() {
        if (arguments.length == 0) {
            sendShortcut('29:1', '46:1', '46:0', '29:0')
        } else {
            copy_.apply(this, arguments)
        }
    }

    global.focusPrevious = function() {
        hide()
    }

    var monitorClipboard_ = monitorClipboard
    monitorClipboard = function() {
        if (isGnome() && env('QT_QPA_PLATFORM') != 'xcb') {
            serverLog('Starting X11 clipboard monitor')
            setEnv('QT_QPA_PLATFORM', 'xcb')
            execute('copyq', '--clipboard-access', 'monitorClipboard')
            serverLog('Stopping X11 clipboard monitor')
            return
        }
        return monitorClipboard_()
    }

    var onClipboardChanged_ = onClipboardChanged
    onClipboardChanged = function() {
        var title = currentWindowTitle()
        if (title)
            setData(mimeWindowTitle, title)
        onClipboardChanged_()
    }

    screenshot = function(format, screenName) {
        if (isSway() || isHyprland())
            return run('grim', '-t', format || 'png', '-')
        return run(
            'spectacle',
            '--background',
            '--nonotify',
            '--pointer',
            '--output',
            '/dev/stdout',
        )
    }

    screenshotSelect = function(format, screenName) {
        if (isSway() || isHyprland()) {
            var geometry = run('slurp')
            geometry = str(geometry).trim()
            return run('grim', '-c', '-g', geometry, '-t', format || 'png', '-')
        }
        return run(
            'spectacle',
            '--background',
            '--nonotify',
            '--pointer',
            '--region',
            '--output',
            '/dev/stdout',
        )
    }

    global.triggerGlobalShortcut = function(commandName) {
        var cmds = commands()
        for (var i in cmds) {
            var cmd = cmds[i]
            if (cmd.isGlobalShortcut && cmd.enable && cmd.name == commandName)
                return action(cmd.cmd)
        }
        throw 'Failed to find enabled global command with given name'
    }"
    1\Icon=
    1\IsScript=true
    1\Name=Wayland Support
    2\Command=copyq: plugins.itempinned.pin()
    2\Icon=
    2\InMenu=true
    2\Input=!OUTPUT
    2\InternalId=copyq_pinned_pin
    2\Name=Pin
    2\Output=application/x-copyq-item-pinned
    3\Command=copyq: plugins.itempinned.unpin()
    3\Icon=
    3\InMenu=true
    3\Input=application/x-copyq-item-pinned
    3\InternalId=copyq_pinned_unpin
    3\Name=Unpin
    4\Command=copyq: plugins.itemtags.tag(decodeURIComponent('Important'))
    4\Icon=
    4\InMenu=true
    4\InternalId=copyq_tags_tag:Important
    4\MatchCommand=copyq: plugins.itemtags.hasTag(decodeURIComponent('Important')) && fail()
    4\Name=Tag as “Important”
    5\Command=copyq: plugins.itemtags.untag(decodeURIComponent('Important'))
    5\Icon=
    5\InMenu=true
    5\InternalId=copyq_tags_untag:Important
    5\MatchCommand=copyq: plugins.itemtags.hasTag(decodeURIComponent('Important')) || fail()
    5\Name=Remove tag “Important”
    6\Command=copyq: plugins.itemtags.tag()
    6\Icon=
    6\InMenu=true
    6\InternalId=copyq_tags_tag
    6\Name=Add a Tag
    7\Command=copyq: plugins.itemtags.untag()
    7\Icon=
    7\InMenu=true
    7\Input=application/x-copyq-tags
    7\InternalId=copyq_tags_untag
    7\Name=Remove a Tag
    8\Command=copyq: plugins.itemtags.clearTags()
    8\Icon=
    8\InMenu=true
    8\Input=application/x-copyq-tags
    8\InternalId=copyq_tags_clear
    8\Name=Clear all tags
    9\Command=copyq: toggle()
    9\GlobalShortcut=meta+q
    9\Icon=
    9\InternalId=copyq_global_toggle
    9\IsGlobalShortcut=true
    9\Name=Show/hide main window
    size=9
  '';
in {
  # https://github.com/adi1090x/rofi
  config = lib.mkIf cfg.rofiConfig.enable {
    home.packages = [
      pkgs.copyq
      pkgs.grim
      pkgs.slurp
    ];
    home.file.".config/copyq/copyq-commands.ini" = {
      text = copyqCommandsConfig;
    };
  };

  options.customHomeManagerModules.copyqConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable copyqConfig config globally or not.
      '';
    };
  };
}
