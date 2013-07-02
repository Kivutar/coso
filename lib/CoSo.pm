package CoSo;
use Dancer ':syntax';
use File::Spec;
use File::Slurp::Unicode;
use RDF::Trine;
use RDF::Query;
#use RDF::Closure;
use Data::Dumper qw<Dumper>;
use Encode;
use utf8;
use URI::Encode qw<uri_decode>;

our $VERSION = '0.1';

# colors
my $colors = {
	'<http://co-so.org/sinogram>'                        => '#444444',
	'<http://co-so.org/sinogram-combination>'            => '#444444',
	'<http://co-so.org/traditional-sinogram>'            => '#000000',
	'<http://co-so.org/current-japanese-sinogram>'       => '#8800ff',
	'<http://co-so.org/vietnamese-sinogram>'             => '#ff8800',
	'<http://co-so.org/vietnamese-sinogram-combination>' => '#ddb500',
	'<http://co-so.org/vietnamese-word-combination>'     => '#ddb500',
	'<http://co-so.org/chu-nom>'                         => '#dcff00',
	'<http://co-so.org/chu-han>'                         => '#ff8800',
};
# sizes
my $sizes = {
	'<http://co-so.org/sinogram>'                        => '10',
	'<http://co-so.org/sinogram-combination>'            => '6',
	'<http://co-so.org/traditional-sinogram>'            => '10',
	'<http://co-so.org/current-japanese-sinogram>'       => '10',
	'<http://co-so.org/vietnamese-sinogram>'             => '10',
	'<http://co-so.org/vietnamese-sinogram-combination>' => '6',
	'<http://co-so.org/vietnamese-word-combination>'     => '5',
	'<http://co-so.org/chu-nom>'                         => '10',
	'<http://co-so.org/chu-han>'                         => '10',
};

my $file = 'db2bis.ttl';

my $store  = RDF::Trine::Store->temporary_store;
my $model  = RDF::Trine::Model->new($store);
my $parser = RDF::Trine::Parser->new('turtle');

my $rdf = read_file($file);
my $uri = 'file://' . File::Spec->rel2abs($file);
$parser->parse_into_model($uri, $rdf, $model);

#my $model = RDF::Closure::Model->new($model, 'RDFS');

get '/individuals' => sub {

	my $query = RDF::Query->new( 'SELECT ?subject ?surclass WHERE {
		?subject <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2002/07/owl#Class> .
		OPTIONAL { ?subject <http://www.w3.org/2000/01/rdf-schema#subClassOf> ?surclass }
	}' );
	my $iterator = $query->execute( $model );

	my @classes;
	while (my $row = $iterator->next) {
		my $class = {};
		$$class{subject} = $$row{subject}->as_string;
		$$class{subject} =~ s/^<|>$//g;
		$$class{label} = get_label("<$$class{subject}>");

		add_subclasses($class);

		push @classes, $class if ! $$row{surclass};
	}

	my $query2 = RDF::Query->new( 'SELECT ?subject ?type WHERE {
		?subject <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> ?type
	}' );
	my $iterator2 = $query2->execute( $model );

	my @data;
	while (my $row = $iterator2->next) {
		my $line = {};
		$$line{subject} = $$row{subject}->as_string;
		$$line{subject} =~ s/^<|>$//g;
		$$line{label} = get_label("<$$line{subject}>");
		$$line{type} = $$row{type}->as_string;
		$$line{type} =~ s/^<|>$//g;
		$$line{typelabel} = get_label("<$$line{type}>");
		push @data, $line if $$line{type} ne 'http://www.w3.org/2002/07/owl#Restriction'
		                 and $$line{type} ne 'http://www.w3.org/2002/07/owl#ObjectProperty'
		                 and $$line{type} ne 'http://www.w3.org/2002/07/owl#Class'
		                 and $$line{type} ne 'http://www.w3.org/2002/07/owl#AllDifferent'
		                 and $$line{type} ne 'http://www.w3.org/2002/07/owl#Ontology'
		                 and $$line{type} ne 'http://www.w3.org/2002/07/owl#FunctionalProperty'
		                 and $$line{type} ne 'http://www.w3.org/2002/07/owl#InverseFunctionalProperty'
		                 and $$line{type} ne 'http://www.w3.org/2002/07/owl#TransitiveProperty'
		                 ;
	}

	template 'individuals.tt', {
		classes => \@classes,
		results => \@data
	};
};

get '/classes' => sub {

	my $query = RDF::Query->new( 'SELECT ?subject ?surclass WHERE {
		?subject <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2002/07/owl#Class> .
		OPTIONAL { ?subject <http://www.w3.org/2000/01/rdf-schema#subClassOf> ?surclass }
	}' );
	my $iterator = $query->execute( $model );

	my @classes;
	while (my $row = $iterator->next) {
		my $class = {};
		$$class{subject} = $$row{subject}->as_string;
		$$class{subject} =~ s/^<|>$//g;
		$$class{label} = get_label("<$$class{subject}>");

		add_subclasses($class);

		push @classes, $class if ! $$row{surclass};
	}

	template 'classes.tt', {
		classes => \@classes,
	};
};

sub count {
	my $uri = shift;

	my $query = RDF::Query->new("SELECT (COUNT(?s) AS ?count) WHERE { ?s <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> $uri }");
	my $iterator = $query->execute($model);
	my $row = $iterator->next;

	return $$row{count}->as_string if $$row{count};
}

sub add_subclasses {
	my $parent = shift;
	$$parent{children} = ();

	my $query = RDF::Query->new( "SELECT ?subject WHERE {
		?subject <http://www.w3.org/2000/01/rdf-schema#subClassOf> <$$parent{subject}>
	}" );
	my $iterator = $query->execute( $model );
	while (my $row = $iterator->next) {
		my $class = {};
		$$class{subject} = $$row{subject}->as_string;
		$$class{instances} = count($$class{subject});
		$$class{subject} =~ s/^<|>$//g;
		$$class{label} = get_label("<$$class{subject}>");

		add_subclasses($class);

		push @{$$parent{children}}, $class;
	}
}

get '/graph' => sub {

	my $query = RDF::Query->new( 'SELECT ?s ?p ?o ?st ?ot ?sl ?ol WHERE { 
		?s ?p ?o . 
		OPTIONAL { ?s <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> ?st } .
		OPTIONAL { ?o <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> ?ot } .
		OPTIONAL { ?s <http://www.w3.org/2000/01/rdf-schema#label> ?sl } .
		OPTIONAL { ?o <http://www.w3.org/2000/01/rdf-schema#label> ?ol } }' );
	my $iterator = $query->execute( $model );

	my @statements;
	while (my $row = $iterator->next) {	
		my $statement = {};
		$$statement{subject} = $$row{s}->as_string;
		$$statement{subject_label} = $$row{sl} ? $$row{sl}->as_string : labelize_uri($$statement{subject});
		$$statement{subject_label} =~ s/^"|"$//g;
		$$statement{subject} =~ s/^<|>$//g;
		$$statement{predicate} = $$row{p}->as_string;
		$$statement{predicate} =~ s/^<|>$//g;
		$$statement{object} = $$row{o}->as_string;
		$$statement{object_label}  = $$row{ol} ? $$row{ol}->as_string : labelize_uri($$statement{object});
		$$statement{object_label} =~ s/^"|"$//g;
		$$statement{object} =~ s/^<|>$//g;

		$$statement{subject_color} = ($$row{st} and $$colors{$$row{st}}) ? $$colors{$$row{st}} : '#000000';
		$$statement{object_color}  = ($$row{ot} and $$colors{$$row{ot}}) ? $$colors{$$row{ot}} : '#000000';

		$$statement{subject_size} = ($$row{st} and $$sizes{$$row{st}}) ? $$sizes{$$row{st}} : '0';
		$$statement{object_size}  = ($$row{ot} and $$sizes{$$row{ot}}) ? $$sizes{$$row{ot}} : '0';

		push @statements, $statement if $$statement{predicate} ne 'http://www.w3.org/2000/01/rdf-schema#label'
									and $$statement{predicate} ne 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
									and $$statement{predicate} ne 'http://www.w3.org/2000/01/rdf-schema#subClassOf'
									and $$statement{predicate} ne 'http://www.w3.org/2000/01/rdf-schema#range'
									and $$statement{predicate} ne 'http://www.w3.org/2000/01/rdf-schema#domain'
									and $$statement{predicate} ne 'http://www.w3.org/2002/07/owl#inverseOf'
									;
	}

	template 'graph.tt', { statements => \@statements };
};

sub labelize {
	my $node = shift;
	my $label;
	if ( $node->is_literal ) {
		$label = $node->as_string;
		$label =~ s/^"|"$//g;
	} else {
		$label = get_label($node);
	}
	return $label;
}

sub get_label {
	my $uri = shift;
	my $label;
	my $query = RDF::Query->new( "SELECT ?o WHERE { $uri <http://www.w3.org/2000/01/rdf-schema#label> ?o }" );
	my $iterator = $query->execute( $model );
	while (my $row = $iterator->next) {
		$label = $$row{o}->as_string;
		$label =~ s/^"|"$//g;
	}
	$label = labelize_uri($uri) unless $label;
	return $label;
}

sub get_type {
	my $uri = shift;
	my $type;
	my $query = RDF::Query->new( "SELECT ?o WHERE { $uri <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> ?o }" );
	if ($query) {
		my $iterator = $query->execute( $model );
		while (my $row = $iterator->next) {
			$type = $$row{o}->as_string;
			$type =~ s/^<|>$//g;
		}
	}
	return $type;
}

sub get_surclass {
	my $uri = shift;
	my $breadcrumb = shift;

	my $parent;
	my $query = RDF::Query->new( "SELECT ?o WHERE { $uri <http://www.w3.org/2000/01/rdf-schema#subClassOf> ?o }" );
	my $iterator = $query->execute( $model );
	while (my $row = $iterator->next) {
		$parent = $$row{o}->as_string;
		$parent =~ s/^<|>$//g;
	}

	if ($parent) {
		push @$breadcrumb, { url => $parent, label => get_label("<$parent>") };
		return get_surclass("<$parent>", $breadcrumb);
	} else {
		return $breadcrumb;
	}
}

sub labelize_uri {
	my $uri = shift;
	my $label = decode_utf8(uri_decode($uri));
	$label =~ s/(.*)(\/|\#)(.*?)>$/$3/;
	return $label;
}

sub sinogram_details {
	my $uri = shift;

	my @aspects;
	my $query = RDF::Query->new( "SELECT ?o WHERE { $uri <http://co-so.org/has-meaning-aspect> ?o }" );
	my $iterator = $query->execute( $model );
	while (my $row = $iterator->next) {
		my $aspect = {};
		$$aspect{text} = $$row{o}->as_string;

		my @combinations;
		my $query2 = RDF::Query->new( "SELECT ?sc ?wc ?cm WHERE {
			$uri <http://co-so.org/has-meaning-aspect> $$aspect{text} .
			?sc <http://co-so.org/contains-sinogram> $uri .
			?sc <http://co-so.org/contains-meaning-aspect> $$aspect{text} .
			OPTIONAL { ?sc <http://co-so.org/has-combination-meaning> ?cm } .
			OPTIONAL { ?wc <http://co-so.org/corresponding-vietnamese-sinogram-combination> ?sc } .
		}" );
		my $iterator2 = $query2->execute( $model );
		while (my $row2 = $iterator2->next) {
			my $combination = {};
			$$combination{subject} = $$row2{sc}->as_string;
			$$combination{subject} =~ s/^<|>$//g;
			$$combination{subject_label} = labelize_uri("<$$combination{subject}>");
			$$combination{meaning} = $$row2{cm};
			$$combination{words} = $$row2{wc}->as_string;
			$$combination{words} =~ s/^<|>$//g;
			$$combination{words_label} = get_label("<$$combination{words}>");
			push @combinations, $combination;
		}
		$$aspect{combinations} = \@combinations;

		push @aspects, $aspect;
	}

	return {
		aspects => \@aspects,
	}
}

sub sinogram_combination_details {
	my $uri = shift;

	my @sinograms;
	my $query = RDF::Query->new( "SELECT ?sg ?ma WHERE {
		$uri <http://co-so.org/contains-sinogram> ?sg .
		$uri <http://co-so.org/contains-meaning-aspect> ?ma .
		?sg <http://co-so.org/has-meaning-aspect> ?ma
	}" );
	my $iterator = $query->execute( $model );
	while (my $row = $iterator->next) {
		my $sinogram = {};
		$$sinogram{subject} = $$row{sg}->as_string;
		$$sinogram{subject_label} = labelize_uri($$sinogram{subject});
		$$sinogram{subject} =~ s/^<|>$//g;
		$$sinogram{aspect} = $$row{ma}->as_string;

		push @sinograms, $sinogram;
	}

	return {
		sinograms => \@sinograms,
	}
}

get qr{/desc/(?<uri> .*)$}x => sub {
	my $uri = decode_utf8(uri_decode(captures->{uri}));

	my $title = get_label("<$uri>");
	my $type = get_type("<$uri>");
	my $color = ($type and $$colors{"<$type>"}) ? $$colors{"<$type>"} : '#000000';
	my $type_label = get_label("<$type>") if $type;
	my $breadcrumb = get_surclass("<$type>", ()) if $type;
	my @breadcrumb = reverse @$breadcrumb if $breadcrumb;

	my $details;
	my $te = engine 'template';
	$details = $te->render($te->view('sinogram_details'), sinogram_details("<$uri>"))
		if $type eq 'http://co-so.org/chu-han'
		or $type eq 'http://co-so.org/chu-nom';
	$details = $te->render($te->view('sinogram_combination_details'), sinogram_combination_details("<$uri>"))
		if $type eq 'http://co-so.org/vietnamese-sinogram-combination';

	my @statements;
	my @extendedstatements;
	my @veryextendedstatements;

	my $query = RDF::Query->new( "DESCRIBE <$uri>" );
	my $iterator = $query->execute( $model );
	while (my $st = $iterator->next) {
		my $statement = {};
		$$statement{subject} = $st->subject->as_string;
		$$statement{subject} =~ s/^<|>$//g;
		$$statement{predicate} = $st->predicate->as_string;
		$$statement{predicate} =~ s/^<|>$//g;
		$$statement{object} = $st->object->as_string;
		$$statement{object} =~ s/^<|>$//g;
		$$statement{subject_label} = get_label("<$$statement{subject}>");
		$$statement{predicate_label} = get_label("<$$statement{predicate}>");
		$$statement{object_label} = labelize($st->object);
		$$statement{is_literal} = $st->object->is_literal;

		my $st = get_type("<$$statement{subject}>");
		my $ot = get_type("<$$statement{object}>");

		$$statement{subject_color} = ($st and $$colors{"<$st>"}) ? $$colors{"<$st>"} : '#000000';
		$$statement{object_color}  = ($ot and $$colors{"<$ot>"}) ? $$colors{"<$ot>"} : '#000000';

		push @statements, $statement if $$statement{predicate} ne 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
									 and $$statement{predicate} ne 'http://www.w3.org/2000/01/rdf-schema#label';
	}

	# for my $statement (@statements) {
	# 	for (($$statement{subject}, $$statement{object})) {
	# 		my $query2 = RDF::Query->new( "DESCRIBE <$_>" ) or next;
	# 		my $iterator2 = $query2->execute( $model );
	# 		while (my $st = $iterator2->next) {
	# 			my $statement = {};
	# 			$$statement{subject} = decode_utf8(uri_decode($st->subject));
	# 			$$statement{subject} =~ s/^<|>$//g;
	# 			$$statement{predicate} = decode_utf8(uri_decode($st->predicate));
	# 			$$statement{predicate} =~ s/^<|>$//g;
	# 			$$statement{object} = decode_utf8(uri_decode($st->object));
	# 			$$statement{object} =~ s/^<|>$//g;
	# 			$$statement{subject_label} = labelize($st->subject);
	# 			$$statement{predicate_label} = labelize($st->predicate);
	# 			$$statement{object_label} = labelize($st->object);

	# 			my $st = get_type("<$$statement{subject}>");
	# 			my $ot = get_type("<$$statement{object}>");

	# 			$$statement{subject_color} = ($st and $$colors{"<$st>"}) ? $$colors{"<$st>"} : '#000000';
	# 			$$statement{object_color}  = ($ot and $$colors{"<$ot>"}) ? $$colors{"<$ot>"} : '#000000';

	# 			push @extendedstatements, $statement if $$statement{predicate} ne 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
	# 												 and $$statement{predicate} ne 'http://www.w3.org/2000/01/rdf-schema#label';
	# 		}
	# 	}
	# }

	# for my $statement (@extendedstatements) {
	# 	for (($$statement{subject}, $$statement{object})) {
	# 		my $query2 = RDF::Query->new( "DESCRIBE <$_>" ) or next;
	# 		my $iterator2 = $query2->execute( $model );
	# 		while (my $st = $iterator2->next) {
	# 			my $statement = {};
	# 			$$statement{subject} = decode_utf8(uri_decode($st->subject));
	# 			$$statement{subject} =~ s/^<|>$//g;
	# 			$$statement{predicate} = decode_utf8(uri_decode($st->predicate));
	# 			$$statement{predicate} =~ s/^<|>$//g;
	# 			$$statement{object} = decode_utf8(uri_decode($st->object));
	# 			$$statement{object} =~ s/^<|>$//g;
	# 			$$statement{subject_label} = labelize($st->subject);
	# 			$$statement{predicate_label} = labelize($st->predicate);
	# 			$$statement{object_label} = labelize($st->object);

	# 			my $st = get_type("<$$statement{subject}>");
	# 			my $ot = get_type("<$$statement{object}>");

	# 			$$statement{subject_color} = ($st and $$colors{"<$st>"}) ? $$colors{"<$st>"} : '#000000';
	# 			$$statement{object_color}  = ($ot and $$colors{"<$ot>"}) ? $$colors{"<$ot>"} : '#000000';
				
	# 			push @veryextendedstatements, $statement if $$statement{predicate} ne 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
	# 													 and $$statement{predicate} ne 'http://www.w3.org/2000/01/rdf-schema#label';
	# 		}
	# 	}
	# }

	template 'desc.tt', {
		breadcrumb => \@breadcrumb,
		uri => $uri,
		title => $title,
		type => $type,
		color => $color,
		type_label => $type_label,
		details => $details,
		statements => \@statements,
		extendedstatements => \@extendedstatements,
		veryextendedstatements => \@veryextendedstatements,
	};
};

true;