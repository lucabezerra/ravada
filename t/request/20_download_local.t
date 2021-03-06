use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');
init($test->connector);

$Ravada::DEBUG=0;
$Ravada::SECONDS_WAIT_CHILDREN = 1;

sub test_download {
    my ($vm, $id_iso) = @_;
    my $iso;
    eval { $iso = $vm->_search_iso($id_iso) };
    if ($@ =~ /No md5/) {
        warn "Probably this release file is obsolete.\n$@";
        return;
    }
    is($@,'');
    unlink($iso->{device}) or die "$! $iso->{device}"
        if $iso->{device} && -e $iso->{device};
    diag("Testing download $iso->{name}");
    my $req1 = Ravada::Request->download(
             id_iso => $id_iso
            , id_vm => $vm->id
            , delay => 4
    );
    is($req1->status, 'requested');

    rvd_back->_process_all_requests_dont_fork();
    is($req1->status, 'done');
    is($req1->error, '') or return;

    my $iso2;
    eval { $iso2 = $vm->_search_iso($id_iso) };
    is($@,'');
    ok($iso2, "Expecting a iso for id = $id_iso , got ".($iso2 or '<UNDEF>'));
    
    my $device;
    eval { $device = $vm->_iso_name($iso2) };
    is($@,'');

    ok($device,"Expecting a device name , got ".($device or '<UNDEF>'));

}

sub test_download_fail {
    my ($vm,$id_iso) = @_;
    my $iso;
    eval { $iso = $vm->_search_iso($id_iso) };
    is($@,'') or return;
    ok($iso->{url},"Expecting url ".Dumper($iso)) or return;
    unlink($iso->{device}) or die "$! $iso->{device}"
        if $iso->{device} && -e $iso->{device};
    $iso->{url} =~ s{(.*)\.(.*)}{$1-failforced.$2};

    my $device;
    eval { $device = $vm->_iso_name($iso) };
    like($@,qr/./);
    ok(!$device);
    ok(!-e $device, "Expecting $device missing") if $device;
}

sub local_urls {
    rvd_back->_set_url_isos('http://localhost/iso/');
}

sub search_id_isos {
    my $vm = shift;
    my $sth=$test->dbh->prepare(
        "SELECT * FROM iso_images"# where name like 'Xubuntu%'"
    );
    $sth->execute;
    my @id_iso;
    while ( my $row = $sth->fetchrow_hashref ) {
        next if !$row->{url};
        eval {$vm->Ravada::VM::KVM::_fetch_filename($row);};
        if ($@ =~ /Can't connect to localhost/) {
            diag("Skipped tests, see http://ravada.readthedocs.io/en/latest/devel-docs/local_iso_server.html");
            return;
        }
        diag($@) if $@ && $@ !~ /No.*found/i;

        if (!$row->{filename}) {
            diag("skipped test $row->{name} $row->{url} $row->{file_re}");
            next;
        }

        push @id_iso,($row->{id});
    }
    return @id_iso;
}
##################################################################


for my $vm_name ('KVM') {
    my $rvd_back = rvd_back();
    local_urls();
    my $vm = $rvd_back->search_vm($vm_name);
    SKIP: {
        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }
        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        test_download_fail($vm, 1);

        for my $id_iso (search_id_isos($vm)) {
            test_download($vm, $id_iso);
        }
    }
}
done_testing();
