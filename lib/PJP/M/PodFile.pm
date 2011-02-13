use strict;
use warnings;
use utf8;

package PJP::M::PodFile;
use Amon2::Declare;
use File::Spec::Functions qw/abs2rel catfile catdir/;
use File::Find::Rule;
use PJP::M::Pod;
use Log::Minimal;

sub retrieve {
	my ($class, $path) = @_;

	my $c = c();
	$c->dbh->single(
		'pod' => {
			path => $path,
		},
	);
}

sub other_versions {
	my ($class, $package) = @_;
	my $c = c();
	@{$c->dbh->selectall_arrayref(q{SELECT distvname, path FROM pod WHERE package=?}, {Slice => {}}, $package)};
}

sub get_latest {
	my ($class, $package) = @_;

	my $c = c();
    my @versions =
      map  { $_->[0] }
      reverse sort { $a->[1] <=> $b->[1] }
      map  { [ $_, eval { version->parse($_) } || 0 ] } map { @$_ } @{
        $c->dbh->selectall_arrayref( q{SELECT distvname FROM pod WHERE package=?},
            {}, $package )
      };
	return undef unless @versions;

	my($path) = $c->dbh->selectrow_array(
		q{SELECT path FROM pod WHERE package=? AND distvname=?}, {}, $package, $versions[0]
	);
	return $path;
}

sub search_by_distvname {
	my ($class, $distvname) = @_;
	my $c = c();
	@{ $c->dbh->selectall_arrayref(q{SELECT package, path, description FROM pod WHERE distvname=? ORDER BY package}, {Slice => {}}, $distvname) };
}

sub generate {
	my ($class, $c) = @_;

	my $txn = $c->dbh->txn_scope();
	$c->dbh->do(q{DELETE FROM pod});
    my @bases = glob(catdir($c->base_dir(), 'assets', '*', 'docs'));
	for my $base (@bases) {
		my @files = File::Find::Rule->file()
									->name('*.pod')
									->in($base);

		for my $file (@files) {
			infof("Processing: %s", $file);
            my $args = $c->cache->file_cache(
                "path:21",
                $file,
                sub {
                    my $html = PJP::M::Pod->pod2html($file);
                    my $relpath = abs2rel( $file, $base );
                    my ( $package, $description ) =
                      PJP::M::Pod->parse_name_section($file);
                    if ( !defined $package ) {
                        $package = $relpath;
                        $package =~ s/\.pod$//;
                        $package =~ s!^modules/!!;
                    }
                    ( my $distvname = $relpath ) =~ s!^modules/!!;
                    $distvname =~ s!^perl/!!;
                    $distvname =~ s!/.+!!;
                    +{
                        path        => $relpath,
                        package     => $package,
                        description => $description,
                        distvname   => $distvname,
                        html        => $html,
                    };
                }
            );
            $c->dbh->replace(
                pod => $args
            );
		}
	}
	$txn->commit;
}

1;

