package XTerm::Util;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Exporter qw(import);
our @ISA       = qw();
our @EXPORT_OK = qw(
                       get_term_bgcolor
                       set_term_bgcolor
               );

our %SPEC;

our %args_get = (
    query_terminal => {
        schema => 'bool*',
        default => 1,
    },
    read_colorfgbg => {
        schema => 'bool*',
        default => 1,
    },
);

our %argopt_quiet = (
    quiet => {
        schema => 'bool*',
        cmdline_aliases => {q=>{}},
    },
);

$SPEC{get_term_bgcolor} = {
    v => 1.1,
    summary => 'Get terminal background color',
    description => <<'_',

Get the terminal's current background color (in 6-hexdigit format e.g. 000000 or
ffff33), or undef if unavailable. This routine tries the following mechanisms,
from most useful to least useful, in order. Each mechanism can be turned off via
argument.

*query_terminal*. Querying the terminal is done via sending the following xterm
 control sequence:

    \e]11;?\a

(or \e]11;?\017). A compatible terminal will issue back the same sequence but
with the question mark replaced by the RGB code, e.g.:

    \e]11;rgb:0000/0000/0000\a

I have tested that this works on the following terminal software (and version)
on Linux:

    MATE Terminal (1.18.2)
    GNOME Terminal (3.18.3)
    Konsole (16.04.3)
    XTerm (330)

And does not work with the following terminal software (and version) on Linux:

    LXTerminal (0.2.0)
    rxvt (2.7.10)

*read_colorfgbg*. Some terminals like Konsole set the environment variable
`COLORFGBG` containing 16-color color code for foreground and background, e.g.:
`15;0`.

_
    args => {
        %args_get,
    },
    result_naked => 1,
};
sub get_term_bgcolor {
    my %args = @_;

    my $rgb;

  QUERY_TERMINAL: {
        last unless $args{query_terminal} // 1;

        last unless -x "/bin/sh";

        require File::Temp;
        my ($fh1 , $fname1) = File::Temp::tempfile();
        my (undef, $fname2) = File::Temp::tempfile();

        my $script = q{#!/bin/sh
oldstty=$(stty -g)
stty raw -echo min 0 time 0
printf "\033]11;?\a"
sleep 0.00000001
read -r answer
result=${answer#*;}
stty $oldstty
echo $result >}.$fname2;

        print $fh1 $script;
        close $fh1;
        system {"/bin/sh"} "/bin/sh", $fname1;

        my $out = do {
            local $/;
            open my $fh2, "<", $fname2;
            scalar <$fh2>;
        };

        unlink $fname1, $fname2;

        if ($out =~ m!rgb:([0-9A-Fa-f]{4})/([0-9A-Fa-f]{4})/([0-9A-Fa-f]{4})\a!) {
            $rgb = substr($1, 0, 2) . substr($2, 0, 2) . substr($3, 0, 2);
            goto DONE;
        }
    } # QUERY_TERMINAL

  READ_COLORFGBG: {
        last unless $ENV{COLORFGBG};
        last unless $ENV{COLORFGBG} =~ /\A[0-1][0-9]?;([0-1][0-9]?)\z/;
        require Color::ANSI::Util;
        $rgb = Color::ANSI::Util::ansi16_to_rgb($1);
        goto DONE;
    } # READ_COLORFGBG

  DONE:
    $rgb;
}

$SPEC{term_bgcolor_is_dark} = {
    v => 1.1,
    summary => 'Check if terminal background color is dark',
    description => <<'_',

This is basically get_term_bgcolor + rgb_is_dark.

_
    args => {
        %args_get,
        %argopt_quiet,
    },
};
sub term_bgcolor_is_dark {
    require Color::RGB::Util;

    my %args = @_;

    my $rgb = get_term_bgcolor(%args);

    my $res_code = !defined($rgb) ? undef :
        Color::RGB::Util::rgb_is_dark($rgb) ? 0:1;
    my $res_text =
        !defined($res_code) ? "Can't get terminal background color" :
        $res_code == 1 ? "Terminal background color '$rgb' is NOT dark" :
        "Terminal background color '$rgb' is dark";
    [
        200,
        "OK",
        $res_code,
        {
            'cmdline.result' => $args{quiet} ? "" : $res_text,
            'cmdline.exit_code' => $res_code // 2,
        },
    ];
}

$SPEC{term_bgcolor_is_light} = {
    v => 1.1,
    summary => 'Check if terminal background color is light',
    description => <<'_',

This is basically get_term_bgcolor + rgb_is_light.

_
    args => {
        %args_get,
        %argopt_quiet,
    },
};
sub term_bgcolor_is_light {
    require Color::RGB::Util;

    my %args = @_;

    my $rgb = get_term_bgcolor(%args);

    my $res_code = !defined($rgb) ? undef :
        Color::RGB::Util::rgb_is_light($rgb) ? 0:1;
    my $res_text =
        !defined($res_code) ? "Can't get terminal background color" :
        $res_code == 1 ? "Terminal background color '$rgb' is NOT light" :
        "Terminal background color '$rgb' is light";
    [
        200,
        "OK",
        $res_code,
        {
            'cmdline.result' => $args{quiet} ? "" : $res_text,
            'cmdline.exit_code' => $res_code // 2,
        },
    ];
}

$SPEC{set_term_bgcolor} = {
    v => 1.1,
    summary => 'Set terminal background color',
    description => <<'_',

Set terminal background color. This prints the following xterm control sequence
to STDOUT (or STDERR, if ~stderr~ is set to true:

    \e]11;#123456\a

where *123456* is the 6-hexdigit RGB color code.

_
    args_as => 'array',
    args => {
        rgb => {
            schema => 'color::rgb24*',
            req => 1,
            pos => 0,
        },
        stderr => {
            schema => 'true*',
            pos => 1,
        },

    },
    result_naked => 1,
};
sub set_term_bgcolor {
    my ($rgb, $stderr) = @_;
    $rgb =~ s/\A#?([0-9A-Fa-f]{6})\z/$1/
        or die "Invalid RGB code '$rgb'";

    local $| = 1;
    my $str = "\e]11;#$rgb\a";
    if ($stderr) {
        print STDERR $str;
    } else {
        print $str;
    }
    return;
}

1;
# ABSTRACT: Utility routines for xterm-compatible terminal (emulator)s

=head1 SYNOPSIS

 use XTerm::Util qw(
     get_term_bgcolor
     set_term_bgcolor
 );

 # when you're on a black background
 say get_term_bgcolor(); # => "000000"

 # when you're on a dark purple background
 say get_term_bgcolor(); # => "310035"

 # set terminal background to dark blue
 set_term_bgcolor("00002b");


=head1 DESCRIPTION

Keywords: xterm, xterm-256color, terminal


=head1 NOTES

Konsole does not support \e]10;?\a (querying VT100 text foreground color), but
xterm does.


=head1 ENVIRONMENT

=head2 COLORFGBG


=head1 SEE ALSO

L<Color::ANSI::Util>

XTerm control sequence:
L<http://invisible-island.net/xterm/ctlseqs/ctlseqs.html>, or
L<http://www.xfree86.org/4.7.0/ctlseqs.html>

=cut
