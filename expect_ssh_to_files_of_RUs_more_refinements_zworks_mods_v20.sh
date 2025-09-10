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
set ping_from_ru_failure 0
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
# Check arguments
if {$argc <= 1} {
    puts stderr "Error: Expected at least 2 arguments, got $argc"
    puts stderr "Usage: $argv0 <file_of_ipaddrs> <file_of_ru_commands> <optional_integer>"
    exit 1
}

set file_of_ipaddrs [lindex $argv 0]
set file_of_ru_commands [lindex $argv 1]
if {$argc == 3} {
    set script_process_number [lindex $argv 2]
    puts "We found 3 arguments for this run. This will be process ID number $script_process_number ."
    }

foreach arg [list $file_of_ipaddrs $file_of_ru_commands] {
    if {[string match "*.*" $arg] || [string match "*/*" $arg]} {
        if {![file exists $arg]} {
            puts stderr "Error: File '$arg' does not exist"
            exit 1
        }
        if {![file readable $arg]} {
            puts stderr "Error: File '$arg' is not readable"
            exit 1
        }
    }
}

puts "All arguments validated successfully"
puts "File of IP addresses: $file_of_ipaddrs"
puts "File of RU commands: $file_of_ru_commands"

#######################################################################################################
# Get line count and timestamp - FIXED: Use exec instead of spawn for simple commands
set line_count [exec wc -l < $file_of_ipaddrs]
set nanoSeconds [exec date +%N]

#######################################################################################################
# proc log_message {message} {
#     puts "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] $message"
# }

# set logFileTimeStamp [exec date +%Y-%m-%d__%H_%M_%S_%N]
# log_file -a "./logs/PeteM_$logFileTimeStamp.txt"
# log_user 1

#######################################################################################################
proc return_line_number_from_file_of_ipaddrs_v2 {ipaddr} {
    global file_of_ipaddrs
    set command "egrep -nw $ipaddr $file_of_ipaddrs | awk -F':' '{ print \$1 }'"
    
    if {[catch {exec bash -c $command} output]} {
        puts "Error executing command: $output"
        return ""
    }
    
    return [string trim $output]
}

#######################################################################################################
proc check_for_stop {ipaddr} {
    if {[file exists "stop"]} {
        puts "\n#### STOP file detected - Script termination requested ***"
        puts "Cleaning up and exiting gracefully, which means deleting the in_progress for $ipaddr marker, if any"
        delete_in_progress_marker $ipaddr
        delete_completed_marker $ipaddr
        sleep 1
        exit 0
    }
    return
}

#######################################################################################################
proc check_for_pause {} {
    if {[file exists "pause"]} {
        puts "\n#### PAUSE file detected - Script execution paused ***"
        # send_user -n "Remove the 'pause' file to resume execution..."
        puts "Remove the 'pause' file to resume execution..."
        
        while {[file exists "pause"]} {
            # send_user -n "."
            puts "."
            sleep 1
        }
        
        puts "*** PAUSE file removed - Resuming script execution ***\n"
    }
    return
}

#######################################################################################################
proc check_ip_marker {ip} {
    set marker_dir "./markers"
    set completed_file "${marker_dir}/${ip}"
    set in_progress_file "${marker_dir}/${ip}_in_progress"

    if {![file exists $marker_dir]} {
        if {[catch {file mkdir $marker_dir} error]} {
            puts "Warning: Could not create markers directory: $error"
            return "error"
        }
    }
    
    if {[file exists $completed_file]} {
        puts "IP $ip already completed (found marker file). Skipping..."
        return "completed"
    }
    
    if {[file exists $in_progress_file]} {
        puts "IP $ip is currently being processed by another instance. Skipping..."
        return "in_progress"
    }
    
    puts "IP $ip is available for processing."
    return "marker_file_not_found"
}

#######################################################################################################
proc create_in_progress_marker {ip} {
    global script_process_number
    set marker_dir "./markers"
    set in_progress_file "${marker_dir}/${ip}_in_progress"

    if {[catch {
        set fd [open $in_progress_file w]
        puts $fd "Started: [clock format [clock seconds]]"
        puts $fd "PID: [pid]"
        puts $fd "Optional script process number: $script_process_number"
        close $fd
    } error]} {
        puts "Warning: Could not create in-progress marker for $ip: $error"
        return false
    }

    puts "Created in-progress marker for $ip"
    return true
}

#######################################################################################################
proc mark_ip_completed {ip} {
    global script_process_number
    set marker_dir "./markers"
    set completed_file "${marker_dir}/${ip}"
    set in_progress_file "${marker_dir}/${ip}_in_progress"

    if {[file exists $in_progress_file]} {
        if {[catch {file delete $in_progress_file} error]} {
            puts "Warning: Could not remove in-progress marker for $ip: $error"
        }
    }

    if {[catch {
        set fd [open $completed_file w]
        puts $fd "Completed: [clock format [clock seconds]]"
        puts $fd "PID: [pid]"
        puts $fd "Optional script process number: $script_process_number"
        close $fd
    } error]} {
        puts "Warning: Could not create completed marker for $ip: $error"
        return false
    }

    puts "Marked $ip as completed"
    return true
}

#######################################################################################################
proc delete_in_progress_marker {ip} {
    set marker_dir "./markers"
    set in_progress_file "${marker_dir}/${ip}_in_progress"

    if {[file exists $in_progress_file]} {
        if {[catch {file delete $in_progress_file} error]} {
            puts "Warning: Could not clean up in-progress marker for $ip: $error"
        } else {
            puts "Cleaned up in-progress marker for $ip"
        }
    }
}

#######################################################################################################
proc delete_completed_marker {ip} {
    set marker_dir "./markers"
    set completed_file "${marker_dir}/${ip}"

    if {[file exists $completed_file]} {
        if {[catch {file delete $completed_file} error]} {
            puts "Warning: Could not clean up completed file marker for $ip: $error"
        } else {
            puts "Cleaned up completed file marker for $ip"
        }
    }
}

#######################################################################################################
# Read files
puts "Now reading in first argument file which contains list of IP addresses, or $file_of_ipaddrs ."
set fp_ips [open $file_of_ipaddrs r]
set ips [split [read $fp_ips] "\n"]
close $fp_ips

puts "Now reading in second argument file which contains list of commands to run on the RU, or $file_of_ru_commands ."
set fp_commands [open $file_of_ru_commands r]
set commands [split [read $fp_commands] "\n"]
close $fp_commands
check_for_stop $ip

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
# FIXED: Main IP processing loop
foreach ip $ips {
    puts "Begin for loop with RU $ip ."
    # puts "Begin for loop with RU $ip which is $RUNumberInFile .."
    set marker_file_status_of_ru [check_ip_marker $ip]
    check_for_pause
    # if {$ip eq ""} {
    #     continue
    # }
    # Validate IP format first to prevent strange values
    # if {![regexp {^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$} $ip]} {
    #     puts "WARNING: Invalid IP format: '$ip' - skipping"
    #     continue
    # }
    #
    # puts "DEBUG: RU Number: $RUNumberInFile, Marker status: $marker_file_status_of_ru"

    switch $marker_file_status_of_ru {
        "completed" {
            # puts "Found the completed marker file for $ip."
            incr completed_marker_files_encountered
        }
        "in_progress" {
            # puts "Found the in_progress marker file for $ip."
            incr in_progress_marker_files_encountered
        }
        "marker_file_not_found" {
            create_in_progress_marker $ip
            set RUNumberInFile [return_line_number_from_file_of_ipaddrs_v2 $ip]
            # send "whoami\r"
            send "\r\n"
            expect {
                -re $interop_whoami {
                    puts "Got the correct prompt for logging into RU $ip which is $RUNumberInFile ."
                }
                timeout {
                    puts "Timeout waiting for expected prompt"
                    delete_in_progress_marker $ip
                    send " exit\r"
                }
                eof {
                    puts "Connection closed unexpectedly"
                    delete_in_progress_marker $ip
                }
            }

            puts "DEBUG: About to ping IP: '$ip'"
            send " ping -c 1 -w 1 $ip\r"
            expect {
                -re "1 packets transmitted, 0 received, 100% packet loss" {
                    # log_message "Ping failure for $ip - skipping SSH attempt"
                    incr ping_failure
                    # puts "$RUNumberInFile,Sorry,Cannot,$ip,Reach,This,RU,ping,failure,maybe,try,again,later,in,the,day,OK,##$script_process_number####"
                    # send "\r"
                    # puts "$RUNumberInFile,Sorry,Cannot,$ip,Reach,This,RU,ping,failure,##$script_process_number####"
                    # send "\r"
                    # delete_in_progress_marker $ip
                    puts "$RUNumberInFile,Sorry,Cannot,$ip,Reach,This,RU,ping,failure,##$script_process_number####"
                    # Consume any remaining output and continue to next IP
                    expect -re {[$#%>] }
                }
                -re "ping: permission denied (are you root?)" {
                    incr ping_from_ru_failure
                    delete_in_progress_marker $ip
                    puts "$RUNumberInFile,Sorry,Cannot,$ip,Ping,From,RU,software,failure,##$script_process_number####"
                    # Consume any remaining output and continue to next IP
                    send " exit\r"
                    expect -re {[$#%>] }
                }

                # Ping timeout - skip SSH completely
                timeout {
                    puts "Ping command timeout for $ip - skipping SSH attempt"
                    incr ping_failure
                    # puts "$RUNumberInFile,Sorry,Cannot,$ip,Reach,This,RU,ping,timeout,maybe,try,again,later,in,the,day,OK,##$script_process_number####"
                    # send "\r"
                    # puts "$RUNumberInFile,Sorry,Cannot,$ip,Reach,This,RU,ping,failure,##$script_process_number####"
                    # send "\r"
                    # Send Ctrl+C to cancel ping and wait for prompt
                    send "\003"
                    #  delete_in_progress_marker $ip
                    puts "$RUNumberInFile,Sorry,Cannot,$ip,Reach,This,RU,ping,failure,##$script_process_number####"
                    expect -re {[$#%>] }
                }

                # Ping success - proceed with SSH logic
                -re "1 packets transmitted, 1 received, 0% packet loss" {
                    # log_message "Ping success for $ip - proceeding with SSH"
                    incr ping_success

                    # Wait for command prompt after ping
                    expect -re {[$#%>] }

                    # Only proceed with SSH if we got the right prompt
                    if {[info exists ru_got_prompt] || 1} {  # Adjust this condition as needed
                        puts "\n--- Attempting to SSH to RU at $ip ---"
                        set logged_in false
                        set connection_failed false

                        puts "\n+++++++++++++++++++++++++++++++++++++++++++++ Login $ru_username1@$ip which is $RUNumberInFile ---"
                        foreach password [list $ru_password1 $ru_password2 $ru_password3] {
                            if {$password eq ""} {
                                continue
                            }

                            puts "\n--- Login $ru_username1@$ip and password $password ---"
                            send " ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -tt $ru_username1@$ip\r"

                            expect {
                                "*password:*" {
                                    puts "\n--- Sending password $password"
                                    send "$password\r"

                                    expect {
                                        "f_5g_du@5G_DU:/var/volatile/tmp$ " {
                                            puts "RU Login successful on $ip with password = $password ."
                                            set ru_password_worked $password
                                            incr successful_RU_logins
                                            set logged_in true
                                            puts "Just logged into $ip which appears on line number $RUNumberInFile of file $file_of_ipaddrs ."
                                            send "\r"
                                            send "RUoutputNumber=$RUNumberInFile\r"
                                            send "script_process_number=$script_process_number\r"
                                            send "nanoSeconds=$nanoSeconds\r"
                                            send "ru_ip=$ip\r"
                                            # send "sleep 5\r"
                                            foreach command $commands {
                                                if {$command eq ""} {
                                                    continue
                                                }
                                                send "$command\r"
                                                expect {
                                                    -re {[$#>] } {
                                                        # Command finished
                                                    }
                                                    timeout {
                                                        puts "Timeout waiting for command output for '$command' on $ip."
                                                    }
                                                }
                                            }
                                            mark_ip_completed $ip
                                            incr completed_marker_files_written
                                            # send "exit\r" # This exit means the file run on RU needs no exit at the bottom
                                            #
                                            send "whoami\r"
                                            expect {
                                                -re $interop_whoami {
                                                    puts "While looping, got the Interop prompt with fjuser1 ID ..."
                                                }
                                                timeout {
                                                    puts "Failed to get proxy-connect prompt which is $interop_whoami for $ip which is $RUNumberInFile ."
                                                    delete_in_progress_marker $ip
                                                    ### Noticed a case where the below line is not necessary:
                                                    # delete_completed_marker $ip
                                                    sleep 2
                                                    send "\r"
                                                    sleep 2
                                                    send "\r"
                                                    send "whoami\r"
                                                    expect {
                                                        -re $interop_whoami {
                                                        puts "2nd chance, While looping, got the Interop prompt with fjuser1 ID ..."
                                                        incr extra_code_hook_exercised
                                                        }
                                                        timeout {
                                                        puts "Again failed to get proxy-connect prompt which is $interop_whoami for $ip which is $RUNumberInFile so exiting."
                                                        exit 1
                                                        }
                                                    }
                                                }
                                            }
                                            # 
                                            expect {
                                                -re {[$#%>] } {
                                                    puts "Successfully disconnected from $ip."
                                                }
                                                timeout {
                                                    puts "Timeout during disconnect from $ip."
                                                    send "\003"
                                                    expect -re {[$#%>] }
                                                }
                                            }
                                        }
                                        timeout {
                                            puts "Timeout waiting for shell prompt on $ip. Trying next password..."
                                            send "\003"
                                            expect -re {[$#%>] }
                                        }
                                        "*Permission denied*" {
                                            incr unsuccessful_RU_logins
                                            puts "Permission denied for $ip using $password. Trying next password..."
                                            send "\003"
                                            expect -re {[$#%>] }
                                        }
                                        "*Connection closed*" {
                                            puts "Connection to $ip closed unexpectedly. Trying next password..."
                                            expect -re {[$#%>] }
                                        }
                                    }
                                }
                                "*) Password:*" {
                                    puts "Connection to $ip appears not to be a known linux system, moving to next IP."
                                    set connection_failed true
                                    send "\r"
                                    puts "$RUNumberInFile,Sorry,Will,$ip,Reach,This,unknown,system,failure,##$script_process_number####"
                                    # send "\r"
                                    delete_in_progress_marker $ip
                                    send "\003"
                                    expect -re {[$#%>] }
                                }
                                "*Connection refused*" {
                                    puts "Connection to $ip refused. Moving to next IP."
                                    set connection_failed true
                                    send "\003"
                                    expect -re {[$#%>] }
                                }
                                "*No route to host*" {
                                    puts "No route to host: $ip. Moving to next IP."
                                    set connection_failed true
                                    send "\003"
                                    expect -re {[$#%>] }
                                }
                                "*Host key verification failed*" {
                                    puts "Host key verification failed for $ip. Moving to next IP."
                                    set connection_failed true
                                    expect -re {[$#%>] }
                                }
                                timeout {
                                    puts "Timeout connecting to $ip. Trying next password..."
                                    send "\003"
                                    expect -re {[$#%>] }
                                }
                            }

                            if {$connection_failed} {
                                break
                            }

                            if {$logged_in} {
                                break
                            }
                        }

                        if {!$logged_in && !$connection_failed} {
                            puts "Failed to log in to $ip with any of the provided passwords."
                            delete_in_progress_marker $ip
                        }

                        puts "\n--------------------------------------------- Logout $ru_username1@$ip which was $RUNumberInFile ---"
                    }
                }
            }
            send "/r"
        }
        "error" {
            puts "Error checking marker for RU $ip, skipping..."
        }
    }

    # puts "Checking for STOP marker..."
    check_for_stop $ip
}
puts "\n--- Script completed ---"
puts "\n=== Environment setup complete ==="
puts "You now have control of the session."
puts "Type 'exit' or press Ctrl+D to disconnect.\n"
puts "#### Successful RU logins: $successful_RU_logins / $line_count lines in the file."
puts "#### Unsuccessful RU passwords: $unsuccessful_RU_logins / $line_count lines in the file."
puts "#### Complete marker files encountered: $completed_marker_files_encountered ."
puts "#### Complete marker files written: $completed_marker_files_written ."
puts "#### In_Progress marker files encountered: $in_progress_marker_files_encountered ."
puts "#### Ping success / ping Failure: $ping_success / $ping_failure ."
puts "#### Ping from RU failure: $ping_from_ru_failure ."
puts "#### Extra code hook exercised: $extra_code_hook_exercised ."
# log_message "#### Successful RU logins: $successful_RU_logins / $line_count lines in the file."
# log_message "#### Unsuccessful RU passwords: $unsuccessful_RU_logins / $line_count lines in the file."
# log_message "#### Complete marker files encountered: $completed_marker_files_encountered ."
# log_message "#### Complete marker files written: $completed_marker_files_written ."
# log_message "#### In_Progress marker files encountered: $in_progress_marker_files_encountered ."
# log_message "#### Ping success / ping Failure: $ping_success / $ping_failure ."
# log_message "#### Extra code hook exercised: $extra_code_hook_exercised ."

set successful_RU_logins 0
set completed_marker_files_encountered 0
set in_progress_marker_files_encountered 0
send "\r"

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
    timeout 1 {
        puts "\nSession timed out due to inactivity"
        send "exit\r"
        expect eof
        exit 0
    }
}

exit 0
