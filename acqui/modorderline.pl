#!/usr/bin/perl

# Copyright 2026 Koha Development Team
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <https://www.gnu.org/licenses>.

=head1 NAME

modorderline.pl

=head1 DESCRIPTION

Bulk-modify a set of order lines selected from the "ordered" report
(acqui/ordered.pl). Up to three fields may be updated in a single
pass:

=over 4

=item * fund (budget_id) - only applied to order lines whose basket
is still open. Order lines belonging to a closed basket are silently
skipped for this field only (everything else selected still applies
to them).

=item * estimated_delivery_date - may be changed regardless of
basket status, the same as moddeliverydate.pl allows for a single
order line.

=item * notes (order_internalnote) - may be changed regardless of
basket status.

=back

=head1 CGI PARAMETERS

=over 4

=item op

'cud-save' to process the bulk update. Any other value (or a direct
GET request) just bounces the user back to C<referrer>.

=item ordernumber

Repeatable. One or more ordernumbers to update.

=item fund_enabled

If true, apply C<fund> as the new budget_id to every selected order
line whose basket is open.

=item fund

The new budget_id to apply when C<fund_enabled> is true.

=item delivery_date_specified

If true, apply C<estimated_delivery_date> (which may be blank, to
clear the date) to every selected order line.

=item estimated_delivery_date

The new estimated delivery date to apply when
C<delivery_date_specified> is true.

=item notes_specified

If true, apply C<notes> (which may be blank, to clear the note) to
every selected order line.

=item notes

The new internal note to apply when C<notes_specified> is true.

=item referrer

Where to send the user back to when done. Defaults to the acquisitions
home page.

=back

=cut

use Modern::Perl;

use CGI qw ( -utf8 );

use C4::Auth        qw( get_template_and_user );
use C4::Output       qw( output_html_with_http_headers );
use C4::Acquisition  qw( GetOrder GetBasket ModOrder );

use Koha::DateUtils qw( dt_from_string );

my $input = CGI->new;
my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name => 'acqui/modorderline.tt',
        query         => $input,
        type          => 'intranet',
        flagsrequired => { acquisition => 'order_manage' },
    }
);

my $op       = $input->param('op') || q{};
my $referrer = $input->param('referrer') || $input->referer() || '/cgi-bin/koha/acqui/acqui-home.pl';

if ( $op eq 'cud-save' ) {
    my @ordernumbers = $input->multi_param('ordernumber');

    my $fund_enabled  = $input->param('fund_enabled')            ? 1 : 0;
    my $date_enabled  = $input->param('delivery_date_specified') ? 1 : 0;
    my $notes_enabled = $input->param('notes_specified')         ? 1 : 0;

    my $new_fund  = $input->param('fund');
    my $new_date  = $input->param('estimated_delivery_date');
    my $new_notes = $input->param('notes');

    my ( @updated, @fund_skipped );

    for my $ordernumber (@ordernumbers) {
        next unless $ordernumber;

        my $order = GetOrder($ordernumber);
        next unless $order;

        my $basket      = GetBasket( $order->{basketno} );
        my $basket_open = $basket && !$basket->{closedate};

        my $changed = 0;

        if ($fund_enabled) {
            if ($basket_open) {
                $order->{budget_id} = $new_fund;
                $changed = 1;
            } else {
                # Fund changes are only allowed while the basket is
                # open; note it so we can tell the user and move on.
                push @fund_skipped, $ordernumber;
            }
        }

        if ($date_enabled) {
            $order->{estimated_delivery_date} = $new_date ? dt_from_string($new_date) : undef;
            $changed = 1;
        }

        if ($notes_enabled) {
            $order->{order_internalnote} = $new_notes;
            $changed = 1;
        }

        if ($changed) {
            ModOrder($order);
            push @updated, $ordernumber;
        }
    }

    my $sep          = ( $referrer =~ /\?/ ) ? '&' : '?';
    my $redirect_url =
          $referrer
        . $sep
        . 'modorderline_updated='
        . scalar(@updated)
        . '&modorderline_fund_skipped='
        . scalar(@fund_skipped);

    print $input->redirect($redirect_url);
    exit;
}

# No valid op - most likely someone browsed here directly. Just show
# a minimal page pointing them back to where they came from.
$template->param( referrer => $referrer );
output_html_with_http_headers $input, $cookie, $template->output;
