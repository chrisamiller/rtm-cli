#! /usr/bin/perl -w

# Command-line interface to www.rememberthemilk.com
# Author: Chris Miller (chrisamiller@gmail.com)
#
# Based loosely on rtm by Yves Rutschle (http://www.rutschle.net/rtm/)
# 
# This program is free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later
# version.
# 
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE.  See the GNU General Public License for more
# details.
# 
# The full text for the General Public License is here:
# http://www.gnu.org/licenses/gpl.html



# Todo:
# 
# add shortcut syntax "r 3"
# add support for date changes
# add support for number ranges "1,2,3" and "1-3"
# uncomplete
# undo


#Prints an authorization URL. This is the first thing you
#should do before using this program. You should then go to
#the specified URL, log in using your username and password,
#and authorize this program to use your data.


# Mark tasks as deleted, complete or uncomplete. I<tasklist>
# is a list of task numbers as returned by --list, with the
# same filter.  Several tasks can be specified separated with
# comas, and ranges with dashes.

#  rtm --list 2 --filter tag:bananas

# I<rtm outputs a list of numbered tasks>

#  rtm --list 2 --filter tag:bananas --complete 3,6,9-12

# I<in that previous list, mark tasks 3, 6 and 9 to 12 as completed>




#libs, etc
use WebService::RTMAgent;
use Pod::Usage;
use Getopt::Long;
use Date::Manip;
use DateTime;
use Data::Dumper;

use strict;


my $ua = new WebService::RTMAgent;



$ua->verbose('');  # /netout|netin/

# These are mine! Please request your own if you're going to build an
# application on top of the RTM module. Otherwise (if you use this rtm script)
# just use them
$ua->api_key("149ce058a1667e914ff370c0e565d77b");
$ua->api_secret("40963b4c7dc48eae");

$ua->no_proxy();
$ua->env_proxy;


my $res;

# my ($param_getauth, $param_complete, $param_list, 
#     $param_filter, $param_delete, $param_uncomplete,
#     $param_show, $param_add, $param_undo,
#     $help, $verbose);



my $verbose = 1;




sub usage{

print " 

Access rememberthemilk.com via the command line 

COMMAND LINE USAGE:

rtm authorize  - prints an authorization URL. This is the 
                 first thing you should do before using this 
                 program. You should then go to the specified 
                 URL, log in using your username and password,
                 and authorize this program to use your data.
                 This only need to be done once.
                 

rtm add <task>
rtm a <task>   - quick add a task



INTERACTIVE USAGE:

(a)dd          - add a task. Parses the string for 
                 dates automatically.

(c)omplete     - complete a task
 
(r)emove       - remove a task from the list

(p)ostpone     - postpones a task - changes the date
                 to one day later

(q) quit       - quit


Not implemented yet:
uncomplete | u
postpone | p
date | d
filter 

This script isn't meant to implement a complete feature 
set, just to make the four or five things I do often easy.
It supports only a single list and a very basic set of 
functions.

Configuration Notes:
rtm can be configured to use a proxy server. Simply
define environment variables 'https_proxy' and 'http_proxy'.
As this is pretty standard, your system might already be
configured accordingly.


SEE ALSO

<WebService::RTMAgent.pm>, which implements the rtm API.


AUTHOR

Chris Miller <chrisamiller\@gmail.com>


CREDITS

Based loosely on rtm by Yves Rutschle (http://www.rutschle.net/rtm/)

";

}


#-----------------------------------------------------
# prints an authorization URL
sub authorize{
     print($ua->get_auth_url."\n");
     exit 0;
}


#-----------------------------------------------------
# Returns a list of tasks depending on filter
sub getTaskList {
    my ($filter,$lastsync) = @_;

    $res = $ua->tasks_getList($filter,$lastsync);
    die $ua->error unless defined $res;

    my @out;
    # for each list
    foreach my $list (@{$res->{tasks}}) {
	# for each task series
        foreach my $taskseries (@{$list->{list}}) {
            my $list_id = $taskseries->{id};
            next unless exists $taskseries->{taskseries};
	    # for each task
            foreach my $task (@{$taskseries->{taskseries}}) {
                my $taskseries_id = $task->{id};
                my $task_id = $task->{task}->[0]->{id};
		my $dueDate = $task->{task}->[0]->{due};
		# if no due date, set it to some unreasonable value so that
		# a simple numerical sort will give us tasks without dates
                # at the end of the list
		if ($dueDate eq ""){
		    $dueDate = 999999999999999;
		}
		else{
		    $dueDate = UnixDate($dueDate,"%s");
		}  
		#push task details onto an array
                push @out, {
                    list_id =>$list_id, 
                    taskseries_id => $taskseries_id, 
                    task_id => $task_id,
                    name => $task->{name},
		    dueDate => $dueDate,
                    task => $task,  # Keep a reference to the whole data
                };
            }
        }
    } 
    #sort by due date, then name, return a hash with numeric keys in sorted order
    my $cnt = 0;
    return map { $cnt++, $_ } sort { $a->{dueDate} <=> $b->{dueDate} || $a->{name} cmp $b->{name} } @out;
}

#-----------------------------------------------------
# after an add, query RTM to get an updated list
# that allows us to use the RTM date parsing
sub updateTaskListPostAdd{
    my ($filter,$lastSync,%list) = @_;
    
    #get the new tasks
    my %newTasks = getTaskList($filter,"last_sync=$lastSync");

    #toss the old and new values into an array
    my @vals = values(%list);
    while (my ($key, $val) = each %newTasks) {	
	push(@vals, $val);
    }

    #sort by due date, then name, return a hash with numeric keys in sorted order
    my $cnt = 0;
    return map { $cnt++, $_ } sort { $a->{dueDate} <=> $b->{dueDate} || $a->{name} cmp $b->{name} } @vals;

}

#-----------------------------------------------------
# after a alteration, update the list we have
# locally - no need to do a server query
sub updateTaskListPostAlter{
    my ($taskNum,$action,$filter,$lastSync,%list) = @_;
    
    # functionally the same, since they won't 
    # show up in the normal,incomplete list
    if ($action eq "delete" || $action eq "complete"){	
	delete($list{$taskNum});	
	#renumber list
	my $cnt = 0;
	my @vals = values(%list);
	return map { $cnt++, $_ } sort { $a->{dueDate} <=> $b->{dueDate} || $a->{name} cmp $b->{name} } @vals;	
    }
    
    
    elsif ($action eq "postpone" || $action eq "date" || $action eq "uncomplete"){
	#get the changes
	my %newTasks = getTaskList($filter,"last_sync=$lastSync");
	#for each change, find it's match and update the hash
	while (my ($key, $val) = each %newTasks) {	
	    if ($val->{'taskseries_id'} eq $list{$taskNum}{'taskseries_id'}){
		$list{$taskNum} = $val;
	    }	
	}
    }#end elsif
    return %list;
}


#-----------------------------------------------------
# after a alteration to date, query server, update task
sub updateTaskListChangeDate{
    my ($filter,$lastSync,%list) = @_;
#    $filter = "filter=status:incomplete" if $filter = "";
    
    #get the changed tasks
    my %newTasks = getTaskList($filter,"last_sync=$lastSync");

    # sort the keys from the existing list
    my @keys = (sort{$a<=>$b}(keys(%list)));
    # get the next number
    my $len = @keys;
    my $last = $keys[$len];    
    
    # hash the new task in the correct place
    while (my ($key, $val) = each %newTasks) {
	$list{$len++} = $val;
    }
    return %list;
}


#-----------------------------------------------------
# Retrieve the list of possible lists
# returns a hash of   number => list hash
# with number guaranteed to be consistent (sorted by list_id)
sub list_lists {
    my $res = $ua->lists_getList;
    die $ua->error if not defined $res;

    my $cnt = 0;                
    return map { $cnt++, $_ } sort { $a->{id} <=> $b->{id} }
                @{$res->{lists}->[0]->{list}};
}

#-----------------------------------------------------
# Turns "1,4,8-12" into a list [1, 4, 8, 9, 11, 12];
# allows for multiple tasks to be altered at once
sub expandList {
    return map {  /(\d+)-(\d+)/ ? ($1..$2): $_; } split ',',$_[0];
}


#-----------------------------------------------------
sub mainLoopTest{
    my $filter = shift(@_);
    my %list = getTaskList($filter,"");
    showList(%list);
#    print Dumper(%list) ."\n" if $verbose;    
    my $lastSync = DateTime->now;
    #addTask("zzzzdddd");
    alterTask("tasks_delete", "5", "deletedd", %list);

    %list = updateTaskListPostAlter("5","delete",$filter,$lastSync,%list);

#    my %newTasks = getTaskList($filter,"last_sync=$lastSync");
#    print Dumper(%newTasks) ."\n";
    showList(%list);
    exit;
}


#####################################################
#interactive loop.  shows list, allows user to act upon it
sub mainLoop {
    my $filter = shift(@_);
    my $quit = 0;
    my $action = "list";    
    my $putList = 1;
    my %list;
    my $lastSync = "";


    while ($quit == 0){
    # check the action
	unless ($action eq ""){
#	    print "checking for action $action\n" if $verbose;
	    #remove a task
	    if (($action eq "rm") || ($action eq "r") || ($action eq "delete")){
		%list = interactiveAlter("delete",$filter,$lastSync,%list);
		$action = "";		
	    }
            #complete a task
	    elsif (($action eq "c") || ($action eq "complete")){		
		%list = interactiveAlter("complete",$filter,$lastSync,%list);
		$action = "";		
	    }
            #uncomplete a task
	    elsif (($action eq "uncomplete") || ($action eq "u")){
		%list = interactiveAlter("uncomplete",$filter,$lastSync,%list);
		$action = "";		
	    }
            #postpone a task
	    elsif (($action eq "postpone") || ($action eq "p")){
		%list = interactiveAlter("postpone",$filter,$lastSync,%list);
		$action = "";		
	    }
	    #add a task
	    elsif (($action eq "add") || ($action eq "a")){
		interactiveAdd();
		%list = updateTaskListPostAdd($filter,$lastSync,%list);
		$lastSync = DateTime->now;
		$action = ""; 
	    }

	    #refresh the entire list
	    elsif (($action eq "list") || ($action eq "l")){
		%list = getTaskList($filter,"");
#		showList(%list);
		$lastSync = DateTime->now;
		$action = "0"
	    }

	    #quit
	    elsif (($action eq "quit") || ($action eq "q")){
		$quit = 1;
		exit;
	    }
	    
	    
	    #invalid input
	    else{
		print "invalid action\n";
	    }
	}	
	
	showList(%list);
	$action = prompt();		       
    }#end while
}#end mainLoop
#####################################################

#-----------------------------------------------------
sub prompt(){
    print "-----------------------------------------------------------------\n";
    print " (a)dd  (r)emove  (c)omplete  (p)ostpone  (q)uit\n\n";
    print ": ";
    my $input = <STDIN>;    
    chomp($input);
    return $input
}

#-----------------------------------------------------
#prompts for task number to alter.
sub interactiveAlter(){
    my ($action,$filter,$lastSync,%list) = @_;
    print "task to $action: ";
    my $taskNum = <STDIN>;
    chomp($taskNum);
    alterTask("tasks_$action", expandList($taskNum), $action . "d", %list);
    return updateTaskListPostAlter($taskNum,$action,$filter,$lastSync,%list);
}

#-----------------------------------------------------
sub interactiveAdd{
    print "task to add: ";
    my $taskName = <STDIN>;
    chomp($taskName);
    print "adding: $taskName \n" if $verbose;
    addTask($taskName)	
}


# #change a task's data
# elsif (($arg0 eq "date") || $arg0 eq "d"){
#     my $taskNum = shift(@ARGV);
#     my $date = shift(@ARGV);
#     foreach my $num (2 .. $#ARGV) {
# 	$date = $date . " " . $ARGV[$num];
#     }
#     unless (defined($taskNum) && defined($date)){
# 	die "invalid task number or date";
#     }
#     setDueDate($taskNum, $date);
# }

# #list only today's tasks
# elsif ($arg0 eq "today"){
#     showList($arg0);
# }

# #show list with provided filter applied
# elsif ($arg0 eq "filter"){
#     my $filter = $ARGV[0];
#     foreach my $num (1 .. $#ARGV) {
# 	$filter = $filter . " " . $ARGV[$num];
#     }
#     showList($filter);
# }






# GetOptions(
#     'authorize'         => \$param_getauth,

#     'add=s'             => \$param_add,
#     'complete=s'        => \$param_complete,
#     'uncomplete=s'      => \$param_uncomplete,
#     'delete=s'          => \$param_delete,

#     'undo:s'            => \$param_undo,

#     'list=i'            => \$param_list,
#     'filter=s'          => \$param_filter,
#     'verbose'           => \$verbose,
#     'show:s'            => \$param_show,
#     'help'              => \$help,





#-----------------------------------------------------
# Adds a task to given list
# takes 1 argument: name of task to add
sub addTask{
    my ($name) = @_;
#    print "adding: $name\n";
    my $res = $ua->tasks_add("name=$name","parse=1","");
    die $ua->error unless defined $res;
    print "Added new task: \"$name\"\n";
}


#-----------------------------------------------------
#alters the task in the specified manner
#
sub alterTask{
    my ($action,$taskList,$message,%list) = @_;
    
    #for each task
    foreach my $taskNum (expandList $taskList) {
	die "task $taskNum does not exist\n" if not exists $list{$taskNum};
#	print "$taskNum\n"
	my %task = %{$list{$taskNum}};
	my ($lid, $tsid, $id, $name) = 
	    @task{'list_id', 'taskseries_id', 'task_id', 'name'};
	
	no strict 'refs';
	my $res = $ua->$action("list_id=$lid","taskseries_id=$tsid","task_id=$id");
	warn $ua->error if not defined $res;
	print "$message `$name'\n"
    }
}


sub setDueDate{
    my ($taskNum,$date) = @_;
    my $action = "tasks_setDueDate";
    my %tasks = getTaskList("filter=status:incomplete","");

    die "task $taskNum does not exist\n" if not exists $tasks{$taskNum};
 
    my %task = %{$tasks{$taskNum}};
    my ($lid, $tsid, $id, $name) = 
	@task{'list_id', 'taskseries_id', 'task_id', 'name'};
    
    no strict 'refs';
    my $res = $ua->$action("list_id=$lid","taskseries_id=$tsid","task_id=$id","due=$date","parse=1");
    warn $ua->error if not defined $res;
    print "Date of \"$name\" changed to $date\n"
}


#-----------------------------------------------------
# I think this will provide cross-platform clearing of the screen.
# haven't tested it on windows yet
sub clearScreen{
    if ($^O =~ /MSWin32/) {
	#windows
	system("cls");
    }
    else {
	#*nix
	system("clear");
    }
}


#-----------------------------------------------------
# retrieves and displays the task list
# TODO: renumber events in date order
# TODO: add filter as option
sub showList{
    clearScreen();
    my (%list) = @_;

#    print Dumper(%list) ."\n";

	
#    # if we have an input filter
#    if (defined $filter){	
#	#Just today's tasks
#	if ($filter eq "today"){
#	    $filter="filter=due:today";
#	    print "\nToday's Tasks:\n";
#	}
#	#user-defined filter
#	elsif ($filter =~ m/\w+\:\w+/){
#	    print "trying your filter: $filter\n";
#	    $filter="filter=". $filter
#	}
#	else{
#	    die "bad filter match"
#	}
#    }
#    else{ #no filter, just show incomplete tasks
#	$filter="filter=status:incomplete";
#    }	    



#     #get the tasks (all incomplete)
#     my %tasks = getTaskList($filter,"");
# #    print Dumper(\%tasks)."\n";

    my $prevDate = 0;

    my @asdf = keys(%list);

    foreach my $i (sort{$a <=> $b} keys %list) {
	
	my $dueDate = $list{$i}->{dueDate};
	#convert blank dueDates
	if ($dueDate == 999999999999999){
	    $dueDate = "___"
	}
	else{ #convert from unix dueDates to "Month Day"
	    $dueDate = UnixDate(ParseDate("epoch $dueDate"),"%b %e");
	}
        
	
	#spacing between days
	unless ("$prevDate" eq "$dueDate"){
	    print "----------------------\n" ;
	}
	
	print "$i:\t" . padName($list{$i}->{name}) . "\t" . $dueDate . "\n";
	$prevDate = $dueDate
    }
    print "\n" #some trailing space for CLI
}


#-----------------------------------------------------
# pads (or truncates) a string to a set number of characters
# for nice display
sub padName {
    my $name=shift;
    my $len = 50;
    if (length($name) < $len){
      $name = sprintf("%-${len}s", $name);
    }
    elsif (length($name) > $len) {
	$name = substr($name,0,$len);
    }
    return $name;
}


# =item B<--undo> [I<action>]

# If no parameter is given, prints a list of the actions that
# can be undone. If a parameter is given, it is the number of
# the action to be undone, as found in that list. (just try
# it, it's quite intuitive really).

# =cut


# if (defined $param_undo) {
#     my $list = $ua->get_undoable;

#     if ($param_undo) {
#         my $t = $list->[$param_undo];
#         die "action $param_undo not found\n" unless $t->{id};
#         $ua->transactions_undo("transaction_id=$t->{id}") or die $ua->error;
#         $ua->clear_undo($param_undo);
#     } else {
#         my $cnt = 0;
#         map { print($cnt++, ": ", $_->{op}, "(",
#                   (join ", ", 
#                       grep { /=/  }  @{$_->{params}}) 
#                   .")\n"); 
#           } @$list;
#     }

# }


# end subs
##############################################################
#begin main

#if parameters are passed
if (@ARGV){
    my $action = shift(@ARGV);

    # print auth URL
    if ($action eq "authorize"){
	authorize();
	exit 0;
    }

    $ua->init;

    # quick add a task
    if (($action eq "add") || ($action eq "a")){
	my $taskName = "";
	#cat arguments into one big string
	foreach my $num (1 .. $#ARGV) {
	    $taskName = $taskName . " " . $ARGV[$num];
	}
	addTask($taskName);	
	exit;
    }

    # list with filter
    elsif (($action eq "filter") || ($action eq "f")){
	#cat arguments into one big string
	my $filter = "";
	foreach my $num (1 .. $#ARGV) {
	    $filter = $filter . " " . $ARGV[$num];
	}
	mainLoop($filter);
    }

    # some other params that aren't recognized 
    # ignore them and enter interactive mode
    else{
	mainLoop("filter=status:incomplete");
    }	
}
#no arguments given, interactive mode
else{
    $ua->init;
    mainLoop("filter=status:incomplete");
    exit;
}




