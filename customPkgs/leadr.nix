{ pkgs }:
let
  sources = import ../npins;
  leadrSrc = sources.leadr;
  inherit (leadrSrc) version;

  # Fish integration script that outputs on --fish
  fishIntegrationScript = pkgs.writeShellScript "leadr-fish-output" ''
        config_file="$HOME/.config/leadr/config.toml"
        leadr_key='""'

        if [ -f "$config_file" ]; then
          leadr_key=$(grep '^leadr_key' "$config_file" | sed 's/leadr_key = "\(.*\)"/\1/')
        fi

        # Convert to fish bind format
        case "$leadr_key" in
          '<C-g>') fish_key='\cg' ;;
          '<C-r>') fish_key='\cr' ;;
          '<C-t>') fish_key='\ct' ;;
          '<C-f>') fish_key='\cf' ;;
          *) fish_key='\cg' ;;
        esac

        cat << EOF
    function __leadr_invoke__
        set -g LEADR_COMMAND_POSITION_ENCODING "#COMMAND"
        set -g LEADR_CURSOR_POSITION_ENCODING "#CURSOR"

        function leadr_cursor_line
            echo 1
        end

        function leadr_parse_flags
            set -l flag_str \$argv[1]
            set -l insert ""
            set -l eval "false"
            set -l exec "false"

            set -l flags_array (string split '+' \$flag_str)
            for flag in \$flags_array
                switch \$flag
                    case "REPLACE" "INSERT" "PREPEND" "APPEND" "SURROUND"
                        set insert \$flag
                    case "EVAL"
                        set eval "true"
                    case "EXEC"
                        set exec "true"
                end
            end

            echo "\$insert|\$eval|\$exec"
        end

        function leadr_extract_cursor_pos
            set -l input \$argv[1]
            if string match -q "*\$LEADR_CURSOR_POSITION_ENCODING*" \$input
                set -l before (string split \$LEADR_CURSOR_POSITION_ENCODING \$input)[1]
                echo (string length \$before)
            else
                echo "-1"
            end
        end

        function leadr_insert_command
            set -l insert_type \$argv[1]
            set -l to_insert \$argv[2]
            set -l cursor_pos \$argv[3]

            switch \$insert_type
                case "INSERT"
                    commandline -i \$to_insert
                case "PREPEND"
                    set -l current (commandline)
                    commandline -r "\$to_insert\$current"
                case "APPEND"
                    commandline -a \$to_insert
                case "SURROUND"
                    set -l before (string split \$LEADR_COMMAND_POSITION_ENCODING \$to_insert)[1]
                    set -l after (string split \$LEADR_COMMAND_POSITION_ENCODING \$to_insert)[2]
                    set -l current (commandline)
                    commandline -r "\$before\$current\$after"
                case "*"
                    commandline -r \$to_insert
            end

            # Set cursor position if specified
            if test \$cursor_pos -ge 0
                commandline -C \$cursor_pos
            end
        end

        function leadr_execute_command
            commandline -f execute
        end

        function leadr_main
            set -l cmd (env LEADR_CURSOR_LINE=(leadr_cursor_line) leadr)

            test -z "\$cmd"; and return

            set -l output_flags (string split ' ' \$cmd)[1]
            set -l to_insert (string sub -s (math (string length \$output_flags) + 2) \$cmd)

            set -l parsed_flags (leadr_parse_flags \$output_flags)
            set -l insert_type (string split '|' \$parsed_flags)[1]
            set -l eval_flag (string split '|' \$parsed_flags)[2]
            set -l exec_flag (string split '|' \$parsed_flags)[3]

            set -l cursor_pos (leadr_extract_cursor_pos \$to_insert)
            if test -n "\$LEADR_CURSOR_POSITION_ENCODING"
                set to_insert (string replace -a \$LEADR_CURSOR_POSITION_ENCODING "" \$to_insert)
            end

            if test "\$eval_flag" = "true"
                set to_insert (eval \$to_insert)
                set cursor_pos -1
            end

            leadr_insert_command \$insert_type \$to_insert \$cursor_pos

            if test "\$exec_flag" = "true"
                leadr_execute_command
            end

            commandline -f repaint
        end

        leadr_main
    end

    # === Key Binding ===
    bind $fish_key __leadr_invoke__
    EOF
  '';

  leadrPackage = pkgs.rustPlatform.buildRustPackage {
    pname = "leadr";
    version = "${version}";

    src = leadrSrc;

    cargoHash = "sha256-trtPj4b0Wd6U4KMNyMgMMO1pmygpDp4oWa/Ab5pra/4=";

    meta = {
      homepage = "https://github.com/ll-nick/leadr";
      description = "Shell aliases on steroids";
      license = pkgs.lib.licenses.mit;
      mainProgram = "leadr";
    };
  };
in
pkgs.symlinkJoin {
  name = "leadr-with-fish-integration";
  paths = [ leadrPackage ];
  buildInputs = [ pkgs.makeWrapper ];

  postBuild = ''
        # Create a wrapper script that handles --fish flag
        rm $out/bin/leadr
        cat > $out/bin/leadr << 'EOF'
    #!/usr/bin/env bash
    if [[ "$1" == "--fish" ]]; then
        exec ${fishIntegrationScript}
    fi
    exec ${leadrPackage}/bin/leadr "$@"
    EOF
        chmod +x $out/bin/leadr
  '';
}
