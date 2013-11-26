foreach (
	{ name=>"ls_language", type=>"set", options => ['french', 'spanish']},
	{ name=>"ls_participant", type=>"int"},
	{ name=>"ls_investigator", type=>'text'},
	{ name=>"ls_round", type=>"set", options => ['pretest','abroad_1','abroad_2','abroad_3','posttest_1','posttest_2','native']},
	{ name=>"ls_round_order", type=>"text" },
	{ name=>"ls_activity_type", type=>"set", options => ['interview','narrative','writing'] },
	{ name=>"ls_activity", type=>"set", options => ['interview','cat_story','brothers_story','sisters_story','drugs','gay_adoption','fast_food'], render_value => 'render_ls_activity'}
)
{
	$c->add_dataset_field( 'eprint', $_);
}

$c->{render_ls_activity} = sub
{
        my( $repository , $field , $value , $alllangs , $nolink , $object ) = @_;

	my $xml = $repository->xml;

	my $frag = $xml->create_document_fragment;

	$frag->appendChild($object->render_value('ls_activity_type'));
	if ($value ne 'interview')
	{
		$frag->appendChild($xml->create_text_node(' ('));
		$frag->appendChild($repository->html_phrase('eprint_fieldopt_ls_activity_' . $value));
		$frag->appendChild($xml->create_text_node(')'));
	}

	return $frag;
};



$c->add_dataset_field( 'document', { name => "content", type => "set", options => ['audio', 'transcript', 'transcript_with_grammar_analysis'], replace_core => 1 });

$c->{mimemap}->{'cha'} = 'text/cha';
$c->{mimemap}->{'cex'} = 'text/mor-pst-cex';
$c->{allow_web_signup} = 0;
$c->{allow_reset_password} = 0;

$c->{set_eprint_automatic_fields} = sub
{
	my ($eprint) = @_;

        $eprint->set_value( "full_text_status", "public" );

	my $title = 'Participant ';
	$title .= EPrints::Utils::tree_to_utf8($eprint->render_value('ls_participant'));
	$title .= ', ';
	$title .= EPrints::Utils::tree_to_utf8($eprint->render_value('ls_round'));
	$title .= ', ';
	$title .= EPrints::Utils::tree_to_utf8($eprint->render_value('ls_activity_type'));
	if ($eprint->value('ls_activity_type') && $eprint->value('ls_activity_type') ne 'interview')
	{
		$title .= ' (' . EPrints::Utils::tree_to_utf8($eprint->render_value('ls_activity')) . ')';
	};
	$eprint->set_value('title', $title);

	#sort out round orderval
	my $map =
	{
		'pretest' => 'a',
		'abroad_1' => 'b',
		'abroad_2' => 'c',
		'abroad_3' => 'd',
		'posttest_1' => 'e',
		'posttest_2' => 'f',
		'native' => 'n',
	};
	$eprint->set_value('ls_round_order', $map->{$eprint->value('ls_round')});


};


$c->{summary_page_metadata} = [qw/
	ls_language
	ls_participant
	ls_investigator
	ls_round
	ls_activity
/];

#stripped down abstract page, using ls_summary_page citation
$c->{eprint_render} = sub
{
	my( $eprint, $repository, $preview ) = @_;

	my $flags = { 
		preview => $preview,
	};
	my %fragments = ();

	my $page = $eprint->render_citation( "ls_summary_page", %fragments, flags=>$flags );

	my $title = $eprint->render_citation("brief");

	my $links = $repository->xml()->create_document_fragment();

	return( $page, $title, $links );
};

$c->{browse_views} = [
        {
                id => "language",
                menus => [
                        {
                                fields => [ "ls_language" ],
                                new_column_at => [10,10],
                        }
                ],
                order => "ls_participant/ls_round_order/ls_activity_type",
                variations => [
                        "DEFAULT;render_fn=ls_render_browse_itempage"
		],
        },
        {
                id => "participant",
                menus => [
                        {
                                fields => [ "ls_participant" ],
                                new_column_at => [10,10],
                        }
                ],
                order => "ls_round_order/ls_activity_type",
                variations => [
                        "DEFAULT;render_fn=ls_render_browse_itempage"
		],
        },
        {
                id => "activity",
                menus => [
                        {
                                fields => [ "ls_activity" ],
                                new_column_at => [10,10],
                        }
                ],
                order => "ls_participant/ls_round_order",
                variations => [
                        "DEFAULT;render_fn=ls_render_browse_itempage"
		],
        },
];

#render method on virtual field for browse rendering
$c->{ls_render_browse_itempage} = sub
{
	my( $repository, $item_list, $view_definition, $path_to_this_page, $filename ) = @_;

	my $xml = $repository->xml();


	my $column_fields = [qw/ ls_language ls_participant ls_round ls_activity /];
	my $extra_columns = ['Files','']; #empty column as the 'Full Record' link doesn't get a heading

	my $frag = $xml->create_document_fragment();

	my $table = $xml->create_element( "table", class => 'browse_list_table');
	$frag->appendChild($table);

	my $tr = $xml->create_element('tr', class => 'heading_row');
	$table->appendChild( $tr );

	foreach my $c (@{$column_fields})
	{
		my $th = $xml->create_element('th');
		$tr->appendChild($th);
		$th->appendChild($repository->html_phrase("ls_summary_table_eprint_fieldname_$c"));
	}
	foreach my $c (@{$extra_columns})
	{
		my $th = $xml->create_element('th');
		$tr->appendChild($th);
		$th->appendChild($xml->create_text_node($c));
	}

	foreach my $item ( @{$item_list} )
	{
		$tr = $xml->create_element( "tr" );
		$table->appendChild( $tr );

		foreach my $c (@{$column_fields})
		{
			my $td = $xml->create_element('td');
			$tr->appendChild($td);
			next unless $item->is_set($c);

			$td->appendChild($item->render_value($c));
		}
		foreach my $c (@{$extra_columns})
		{
			if ($c eq 'Files')
			{
				my $td = $xml->create_element('td');
				$tr->appendChild($td);

				my $ul = $xml->create_element('ul');
				$td->appendChild($ul);

				#collect audio documents
				my $audio_urls = [];
				foreach my $doc ($item->get_all_documents)
				{
					if ($doc->value('format') eq 'audio')
					{
						push@{$audio_urls}, $doc->url;
					}
					my $li = $xml->create_element('li');
					$ul->appendChild($li);
					my $a = $xml->create_element('a', href => $doc->url);
					$li->appendChild($a);
					$a->appendChild($xml->create_text_node($doc->value('main')));
				}
#disabled because of pre-loading bandwidth
#				if (scalar @{$audio_urls})
#				{
#					my $audio = $xml->create_element('audio', controls => 'controls');
#					$td->appendChild($audio);
#					foreach my $url (@{$audio_urls})
#					{
#						my $source = $xml->create_element('source', src => $url);
#						$audio->appendChild($source);
#					}
#				}
			}
		}
		my $td = $xml->create_element('td');
		$tr->appendChild($td);
		my $a = $xml->create_element('a', href => $item->url);
		$td->appendChild($a);
		$a->appendChild($xml->create_text_node('Full Record...'));
	}

	return $frag;
};

