#!/usr/bin/perl -I/usr/share/eprints/perl_lib

use strict;
use warnings;

use EPrints;
use File::Find::Rule;

my $ep = EPrints->new();
my $repo = $ep->repository('langsnap');
my $eprint_ds = $repo->dataset('eprint');
my $doc_ds = $repo->dataset('document');
exit unless $repo;

my $base = '/data/langsnap_data';

my @files = File::Find::Rule->file()->in($base);

my $ps = {};

my $data = {};
foreach my $file (@files)
{
	my @parts = split(/\//, $file);
	my $filename = $parts[$#parts];

	if ($filename =~ m/([A-Z])([0-9]*)([a-z])([A-Zc]*)\.([A-Za-z3\.]+)$/)
	{
		my ($activity, $participant, $visit, $investigator, $extension) = ($1,$2,$3,$4,$5);

		push @{$data->{$participant}->{$visit}->{$activity}},
		{
			participant => $participant,
			visit => $visit,
			activity => $activity,
			file => $file,
			filename => $filename,
			investigator => $investigator,
			extension => $extension,
		}
	}
	else
	{
		print STDERR "$file doesn't match\n";
		exit;
	}

}

foreach my $participant (values %{$data})
{
	foreach my $visit (values %{$participant})
	{
		foreach my $activity (values %{$visit})
		{
#			my $obj = $ds->create_object;

			my $data = {
				'eprint_status' => 'archive',
				'userid' => 1,
			};

			foreach my $fieldname (qw/ ls_language ls_participant ls_investigator ls_round ls_round_order ls_activity_type ls_activity /)
			{
				$data->{$fieldname} = val($fieldname, $activity);
			}

			my $eprint = $eprint_ds->create_dataobj($data);

			foreach my $f (sort sort_files @{$activity})
			{
				my $doc = $eprint->create_subdataobj( "documents", {
					main => $f->{filename},
					content => file_type($f),
					format => file_format($f),
					formatdesc => file_format_description($f)
				});

				my $file = $doc->add_file($f->{file}, $f->{filename});
				$file->set_value('mime_type', $repo->call('guess_doc_type', $repo, $f->{file}));
				$file->commit;
				$doc->commit;
			}
			$eprint->commit;
		}
	}
}

sub sort_files
{
	my $map = {
		'wav' => 2,
		'mp3' => 1,
		'cha' => 3,
		'mor.pst.cex' => 4,
	};
	
	return $map->{lc($a->{extension})} <=> $map->{lc($b->{extension})};

}

sub create_file_data
{
	my ($f) = @_;

	$data = {};
	$data->{filename} = $f->{filename};
	$data->{file} = $f->{file};
	$data->{filesize} = -s $f->{file};

	return $data;
}




sub file_format_description
{
	my ($data) = @_;

	my $map = {
		'mp3' => "MP3",
		'wav' => "Uncompressed",
		'cha' => "Transcript",
		'mor.pst.cex' => "Transcript with Grammar Analysis",
	};

	return $map->{lc($data->{extension})};
}

sub file_format
{
	my ($data) = @_;

	my $map = {
		'wav' => "audio",
		'mp3' => "audio",
		'cha' => "text",
		'mor.pst.cex' => "text",
	};

	my $t = $map->{lc($data->{extension})};
	die "Unknown type for " . $data->{extension} . "\n" unless $t;
	return $t;

}

sub file_type
{
	my ($data) = @_;
#> WAV  (audio, file extension .wav)
#> MP3 (audio, file extension .mp3)
#> Transcript (transcribed text, file extension .cha)
#> Tagged (transcribed text + grammatical analysis, file extension .mor.pst.cex)

	my $map = {
		'wav' => "audio",
		'mp3' => "audio",
		'cha' => "transcript",
		'mor.pst.cex' => "transcript_with_grammar_analysis",
	};

	my $t = $map->{lc($data->{extension})};
	die "Unknown type for " . $data->{extension} . "\n" unless $t;
	return $t;
}

sub val
{
	my ($fieldname, $data) = @_;

	if ($fieldname eq 'ls_round')
	{
		my $map =
		{
			'a' => 'pretest',
			'b' => 'abroad_1',
			'c' => 'abroad_2',
			'd' => 'abroad_3',
			'e' => 'posttest_1',
			'f' => 'posttest_2',
			'n' => 'native',
		};

		my $round = $map->{$data->[0]->{visit}};
		die "Unknown round\n" unless $round;
		return $round;
	}

	if ($fieldname eq 'ls_round_order')
	{
		return $data->[0]->{visit};
	}

	if ($fieldname eq 'ls_investigator')
	{
		my $i = $data->[0]->{investigator};
		return $i;
	}

	if ($fieldname eq 'ls_language')
	{
		my $l = from_annotation('@languages', $data);
		return 'french' if $l =~ m/fr/;
		return 'spanish' if $l =~ m/sp/;
die 'Unknown Language';
	}

	if ($fieldname eq 'ls_participant')
	{
		return $data->[0]->{participant};
	}

	if ($fieldname eq 'ls_activity_type')
	{
		my $map = {
			O => 'interview',
			C => 'narrative',
			B => 'narrative',
			S => 'narrative',
			G => 'writing',
			D => 'writing',
			F => 'writing'
		};
		my $code = $data->[0]->{activity};
		die ("Unknown code $code\n" . $data->[0]->{file} . "\n") unless $map->{$code};
		return $map->{$code};
	}

	if ($fieldname eq 'ls_activity')
	{
		my $map = {
			O => 'interview',
			C => 'cat_story',
			B => 'brothers_story',
			S => 'sisters_story',
			G => 'gay_adoption',
			D => 'drugs',
			F => 'fast_food'
		};
		my $code = $data->[0]->{activity};
		die ("Unknown code $code\n" . $data->[0]->{file} . "\n") unless $map->{$code};
		return $map->{$code};
	}

	die "Unhandled field $fieldname\n";
}



sub from_annotation
{
	my ($tag, $data) = @_;

	foreach my $r (@{$data})
	{
		if ($r->{extension} eq 'mor.pst.cex')
		{
			open FILE, $r->{file} or die 'Cannot open ' . $r->{file} . "\n";
			my $l;
			while (<FILE>)
			{
				if (lc($_) =~ m/^\Q$tag\E(.*)$/)
				{
					close FILE;
					return $1;
				}
			}
			close FILE;
		}
	}



}



