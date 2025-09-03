#!/usr/bin/expect -f

#######################################################################################################
# Set variables
set jump_server1 ""
set username1 ""
set password1 ""
set timeout 30
set jump_server2 ""
set username2 ""
set password2 ""
set ru_username1 ""
set ru_username2 ""
set ru_password1 ""
set ru_password2 ""
set ru_password3 ""
set ru_password_worked ""
set successful_RU_logins 0
set unsuccessful_RU_logins 0
set completed_marker_files_encountered 0
set completed_marker_files_written 0
set in_progress_marker_files_encountered 0
set interop_whoami "fjuser1"
set ip 8.8.8.8
set marker_file_status_of_ru "unknown"
set RUNumberInFile 0
set marker_file_status_of_ru "unknown"
set ping_success 0
set ping_failure 0
set script_process_number ""
set extra_code_hook_exercised 0

#######################################################################################################
# Read configuration file (removed duplicate section)
set config_file "config.txt"
if {![file exists $config_file]} {
    puts "Error: Configuration file '$config_file' not found!"
    exit 1
}

if {[catch {open $config_file r} config_fd]} {
    puts "Error: Unable to open configuration file '$config_file': $config_fd"
    exit 1
}

while {[gets $config_fd line] >= 0} {
    if {[string trim $line] eq "" || [string match "#*" [string trim $line]] || [string match ";*" [string trim $line]]} {
        continue
    }

    if {[regexp {^([^=]+)=(.*)$} $line match key value]} {
        set key [string trim $key]
        set value [string trim $value]

        if {[regexp {^"(.*)"$} $value match unquoted_value]} {
            set value $unquoted_value
        } elseif {[regexp {^'(.*)'$} $value match unquoted_value]} {
            set value $unquoted_value
        }

        switch -exact $key {
            "jump_server1" {
                set jump_server1 $value
                puts "Loaded jump_server1: $jump_server1"
            }
            "username1" {
                set username1 $value
                puts "Loaded username1: $username1"
            }
            "password1" {
                set password1 $value
                puts "Loaded password1: [string repeat "*" [string length $password1]]"
            }
            "timeout" {
                if {[string is integer $value] && $value > 0} {
                    set timeout $value
                    puts "Loaded timeout: $timeout"
                } else {
                    puts "Warning: Invalid timeout value '$value', using default: $timeout"
                }
            }
            "jump_server2" {
                set jump_server2 $value
                puts "Loaded jump_server2: $jump_server2"
            }
            "username2" {
                set username2 $value
                puts "Loaded username2: $username2"
            }
            "password2" {
                set password2 $value
                puts "Loaded password2: [string repeat "*" [string length $password2]]"
            }
            "ru_username1" {
                set ru_username1 $value
                puts "Loaded ru_username1: $ru_username1"
            }
            "ru_username2" {
                set ru_username2 $value
                puts "Loaded ru_username2: $ru_username2"
            }
            "ru_password1" {
                set ru_password1 $value
                puts "Loaded ru_password1: $ru_password1"
            }
            "ru_password2" {
                set ru_password2 $value
                puts "Loaded ru_password2: $ru_password2"
            }
            "ru_password3" {
                set ru_password3 $value
                puts "Loaded ru_password3: $ru_password3"
                # FIXED: Set ru_password_worked to ru_password3, not ru_password1
                set ru_password_worked $ru_password3
                puts "Loaded ru_password_worked: $ru_password_worked"
            }
            default {
                puts "Warning: Unknown configuration key '$key' ignored"
            }
        }
    } else {
        puts "Warning: Invalid configuration line ignored: $line"
    }
}

close $config_fd

set required_vars [list jump_server1 username1 password1 ru_username1]
set missing_vars [list]

foreach var $required_vars {
    if {[set $var] eq ""} {
        lappend missing_vars $var
    }
}

if {[llength $missing_vars] > 0} {
    puts "Error: Missing required configuration variables: [join $missing_vars ", "]"
    exit 1
}

puts "Configuration loaded successfully!"
puts "Using timeout: $timeout seconds"

#######################################################################################################
# SSH connections
spawn ssh -C -L 9998:localhost:9998 -L 33891:localhost:3389 -tt $username1@$jump_server1 -p9922

expect {
    "Are you sure you want to continue connecting" {
        send "yes\r"
        exp_continue
    }
    "Password:" {
        send "$password1\r"
    }
    "password:" {
        send "$password1\r"
    }
    timeout {
        puts "Connection timed out"
        exit 1
    }
    eof {
        puts "Connection failed"
        exit 1
    }
}

expect {
    -re {[$#%>] } { }
    timeout {
        puts "Failed to get shell prompt"
        exit 1
    }
}
puts "Successfully logged into first jump server"

send "proxy-connect\r"
send " cd /home/fjuser1/RFTAC/Pete\r"
send "whoami\r"
expect {
    -re $interop_whoami {
        puts "Reached the 2nd jump server's Interop prompt with fjuser1 ID ..."
    }
    timeout {
        puts "Failed to get proxy-connect prompt"
        exit 1
    }
}
puts "Successfully logged into 2nd jump server"

#######################################################################################################
# FIXED: Properly close interact block
interact {
    \003 {
        send "\003"
    }
    \004 {
        send "exit\r"
        puts "\nDisconnecting..."
        expect eof
        exit 0
    }
    # timeout 1 {
    #     puts "\nSession timed out due to inactivity"
    #     send "exit\r"
    #     expect eof
    #     exit 0
    # }
}

exit 0
