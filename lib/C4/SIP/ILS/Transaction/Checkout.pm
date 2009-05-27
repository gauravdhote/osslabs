#
# An object to handle checkout status
#

package ILS::Transaction::Checkout;

use warnings;
use strict;

use POSIX qw(strftime);
use Sys::Syslog qw(syslog);
use Data::Dumper;
use CGI;

use ILS;
use ILS::Transaction;

use C4::Context;
use C4::Circulation;
use C4::Members;
use C4::Debug;

use vars qw($VERSION @ISA $debug);

BEGIN {
	$VERSION = 1.02;
	@ISA = qw(ILS::Transaction);
}

# Most fields are handled by the Transaction superclass
my %fields = (
	      security_inhibit => 0,
	      due              => undef,
	      renew_ok         => 0,
	);

sub new {
    my $class = shift;;
    my $self = $class->SUPER::new();
    my $element;
    foreach $element (keys %fields) {
		$self->{_permitted}->{$element} = $fields{$element};
    }
    @{$self}{keys %fields} = values %fields;
#    $self->{'due'} = time() + (60*60*24*14); # two weeks hence
	$debug and warn "new ILS::Transaction::Checkout : " . Dumper $self;
    return bless $self, $class;
}

sub do_checkout {
	my $self = shift;
	syslog('LOG_DEBUG', "ILS::Transaction::Checkout performing checkout...");
	my $barcode        = $self->{item}->id;
	my $patron_barcode = $self->{patron}->id;
	$debug and warn "do_checkout: patron (" . $patron_barcode . ")";
	# my $borrower = GetMember( $patron_barcode, 'cardnumber' );
	# my $borrower = $self->{patron};
	# my $borrower = GetMemberDetails(undef, $patron_barcode);
	my $borrower = $self->{patron}->getmemberdetails_object();
	$debug and warn "do_checkout borrower: . " . Dumper $borrower;
	my ($issuingimpossible,$needsconfirmation) = CanBookBeIssued( $borrower, $barcode );
	my $noerror=1;
	foreach ( keys %$issuingimpossible ) {
		# do something here so we pass these errors
		$self->screen_msg($issuingimpossible->{$_});
		$noerror = 0;
	}
	foreach my $confirmation ( keys %$needsconfirmation ) {
		if ($confirmation eq 'RENEW_ISSUE'){
			my ($renewokay,$renewerror)= CanBookBeRenewed($borrower->{borrowernumber},$self->{item}->{itemnumber});
			if (! $renewokay){
				$noerror = 0;
				warn "cannot renew $borrower->{borrowernumber} $self->{item}->{itemnumber} $renewerror";
			}
		} else {
			$self->screen_msg($needsconfirmation->{$confirmation});
			$noerror = 0;
		}
	}
	unless ($noerror) {
		warn "cannot issue: " . Dumper $issuingimpossible . "\n" . $needsconfirmation;
		$self->ok(0);
		return $self;
	}
	# can issue
	$debug and warn "do_checkout: calling AddIssue(\$borrower,$barcode, undef, 0)\n"
		# . "w/ \$borrower: " . Dumper($borrower)
		. "w/ C4::Context->userenv: " . Dumper(C4::Context->userenv);
	my $c4due  = AddIssue( $borrower, $barcode, undef, 0 );
	my $due  = $c4due->output('iso') || undef;
	$debug and warn "Item due: $due";
	$self->{'due'} = $due;
	$self->{item}->due_date($due);
	$self->ok(1);
	return $self;
}

1;
__END__
