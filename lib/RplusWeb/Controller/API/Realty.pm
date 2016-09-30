package RplusWeb::Controller::API::Realty;

use Mojo::Base 'Mojolicious::Controller';


use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
#use Rplus::Model::RealtyCodesExt;
#use Rplus::Model::RealtyCodesExt::Manager;
use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;

use Rplus::Util::Query;

use Data::Dumper;
use JSON;
sub _generate_code {
    srand(time);
    my $sz = shift;
    my @chars = ("A".."Z", "0".."9");
    my $code;
    $code .= $chars[rand @chars] for 1..$sz;

    return $code;
}

# PhoneNum parser helper
sub _parse_phone_num  {
    my ($phone_num, $phone_prefix) = @_;
    return undef unless $phone_num;

    if ($phone_num !~ /^\d{10}$/) {
        $phone_num =~ s/\D//g;
        $phone_num =~ s/^(7|8)(\d{10})$/$2/;
        $phone_num = $phone_prefix.$phone_num if "$phone_prefix$phone_num" =~ /^\d{10}$/;
        return undef unless $phone_num =~ /^\d{10}$/;
    }
    return $phone_num;
}

sub list {
    my $self = shift;
    my $offer_type_code = $self->param('offer_type_code');
    my $q = $self->param('q');
    my $type_code = $self->param('type_code');
    my $district = $self->param('district');
    my $rooms_count = $self->param('rooms_count');
    my $price_low = $self->param('price_low');
    my $price_high = $self->param('price_high');
    my $per_page = $self->param('per_page');
    my $page = $self->param('page');
    my $sort_by = $self->param('sort_by');
    my $sort_by_q = 'change_date DESC';
    $sort_by_q = 'price ASC' if ($sort_by eq 'price');

    my @query = (
        state_code => 'work',
        offer_type_code => $offer_type_code,
        ($type_code ? (type_code => $type_code) : ()),
        ($district ? (district => $district) : ()),
        ($rooms_count ? ($rooms_count =~ /^\d$/ ? ($rooms_count <= 4 ? (rooms_count => $rooms_count) : (rooms_count => {ge => 5})) : ()) : ()),
        ($price_low && $price_high ? (price => {ge_le => [$price_low, $price_high]}) : ($price_low ? (price => {ge => $price_low}) : ($price_high ? (price => {le => $price_high}) : ()))),
        Rplus::Util::Query->parse($q, $self),
    );

    my $res = {
        list => [],
        count => Rplus::Model::Realty::Manager->get_objects_count(query => [@query], require_objects => ['type']) + 1,
    };

    # Небольшой костыль: если ничего не найдено, удалим FTS данные
    if (!$res->{count}) {
        @query = map { ref($_) eq 'SCALAR' && $$_ =~ /^fts/ ? () : $_ } @query;
        $res->{count} = Rplus::Model::Realty::Manager->get_objects_count(query => [@query, account_id => 4,], require_objects => ['type']);
    }

    my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator(
        query => [
            @query
        ],
        require_objects => ['type'],
        with_objects => ['address_object', 'sublandmark', 'ap_scheme', 'house_type', 'room_scheme', 'condition', 'balcony', 'bathroom'],
        sort_by => $sort_by_q,
        page => $page,
        per_page => $per_page,
    );
    while (my $realty = $realty_iter->next) {
        my $street = '';
        if ($realty->address_object_id) {
            my $ap = from_json($realty->address_object->metadata)->{'addr_parts'};
            $street = $ap->[0]->{'name'}.($ap->[0]->{'short_type'} ne 'ул' ? ' '.$ap->[0]->{'full_type'} : '');
        }

        my (@digest, $squares, $squares_land, $floors);
        {
            push @digest, $realty->type->name;
            push @digest, ($realty->rooms_count && $realty->rooms_offer_count ? $realty->rooms_offer_count.'к из '.$realty->rooms_count.'к' : $realty->rooms_count.'к') if $realty->rooms_count;
            push @digest, from_json($realty->ap_scheme->metadata)->{'description'} || $realty->ap_scheme->name if $realty->ap_scheme_id;
            push @digest, from_json($realty->house_type->metadata)->{'description'} || $realty->house_type->name if $realty->house_type_id;
            push @digest, from_json($realty->room_scheme->metadata)->{'description'} || $realty->room_scheme->name if $realty->room_scheme_id;
            $floors = join('/', $realty->floor || (), $realty->floors_count || ()) if $realty->floor || $realty->floors_count;
            push @digest, $floors.' эт.' if $floors;
            $squares = join('/', $realty->square_total || (), $realty->square_living || (), $realty->square_kitchen || ()).' м²' if $realty->square_total || $realty->square_living || $realty->square_kitchen;
            push @digest, $squares if $squares;
            $squares_land = $realty->square_land.($realty->square_land_type || 'ar' eq 'ar' ? ' сот.' : ' га.') if $realty->square_land;
            push @digest, $squares_land if $squares_land;
            push @digest, from_json($realty->condition->metadata)->{'description'} || $realty->condition->name if $realty->condition_id;
            push @digest, from_json($realty->balcony->metadata)->{'description'} || $realty->balcony->name if $realty->balcony_id;
            push @digest, from_json($realty->bathroom->metadata)->{'description'} || $realty->bathroom->name if $realty->bathroom_id;
            #push @digest, $realty->description if $realty->description;
        }

        my $x = {
            id => $realty->id,
            type => $realty->type->name,
            street => $street,
            district => $district,
            rooms_count => $realty->rooms_count,
            rooms_offer_count => $realty->rooms_offer_count,
            squares => $squares,
            squares_land => $squares_land,
            floors => $floors,
            price => $realty->price,
            digest => join(', ', @digest),
            #last_seen_date => $realty->last_seen_date,
            change_date => $realty->change_date,
        };

        push @{$res->{list}}, $x;
    }

    # Load _main_ photos
    for (@{$res->{list}}) {
        my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $_->{id}, delete_date => undef], sort_by => 'id ASC');
        #if ($photo) {
        #    $res->{hash}->{$photo->realty_id}->{main_photo_thumbnail} = $photo->thumbnail_filename;
        #}
        #my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => [keys %{$res->{hash}}], delete_date => undef], sort_by => 'is_main DESC, id ASC');
        while (my $photo = $photo_iter->next) {
            next if $_->{main_photo_thumbnail};
            $_->{main_photo_thumbnail} = $photo->thumbnail_filename;
        }
    }
    return $self->render(json => $res);
}

sub get {
    my $self = shift;

    my $id = $self->param('id');

    my $realty = Rplus::Model::Realty::Manager->get_objects(
        query => [id => $id, state_code => 'work'],
        require_objects => ['type', 'offer_type'],
        with_objects => ['address_object', 'sublandmark', 'ap_scheme', 'house_type', 'room_scheme', 'condition', 'balcony', 'bathroom', 'agent'],
    )->[0];
    return $self->render_not_found unless $realty;

    my $street = '';
    my $district = '';
    if ($realty->address_object_id) {
        my $ap = from_json($realty->address_object->metadata)->{'addr_parts'};
        $street = $ap->[0]->{'name'}.($ap->[0]->{'short_type'} ne 'ул' ? ' '.$ap->[0]->{'full_type'} : '');
    }

    my $squares = join('/', $realty->square_total || (), $realty->square_living || (), $realty->square_kitchen || ()).' м²' if $realty->square_total || $realty->square_living || $realty->square_kitchen;
    my $squares_land = $realty->square_land.($realty->square_land_type || 'ar' eq 'ar' ? ' сот.' : ' га.') if $realty->square_land;
    my $floors = join('/', $realty->floor || (), $realty->floors_count || ()) if $realty->floor || $realty->floors_count;

    my $res = {
        id => $realty->id,
        type => $realty->type->name,
        offer_type => $realty->offer_type->name,
        street => $street,
        district => $district,
        rooms_count => $realty->rooms_count,
        squares => $squares,
        squares_land => $squares_land,
        floors => $floors,
        price => $realty->price,
        description => $realty->description,
        ap_scheme => $realty->ap_scheme_id ? $realty->ap_scheme->name : '',
        room_scheme => $realty->room_scheme_id ? $realty->room_scheme->name : '',
        condition => $realty->condition_id ? $realty->condition->name : '',
        balcony => $realty->balcony_id ? $realty->balcony->name : '',
        bathroom => $realty->bathroom_id ? $realty->bathroom->name : '',
        photos => [],
        owner_phones => [],
        lat => $realty->latitude,
        lon => $realty->longitude,
    };

    if ($self->session->{'user'}) {
      $res->{owner_phones} = $realty->owner_phones;
      $res->{session} = $self->session->{'user'}->{email};
    }

    my $photo_iter = Rplus::Model::Photo::Manager->get_objects_iterator(query => [realty_id => $id, delete_date => undef], sort_by => 'is_main DESC, id ASC');
    while (my $photo = $photo_iter->next) {
        push @{$res->{photos}}, $photo->filename;
    }

    return $self->render(json => {data => $res});
}

sub abuse {
    my $self = shift;
    my $id = $self->param('realty_id');
    return $self->render(json => {result => 'ok'});
}

sub get_max_price {
    my $self = shift;
    my $max_price = 50; #$self->db->dbh->selectall_arrayref(q{SELECT MAX(price) FROM realty WHERE offer_type_code like 'rent' AND state_code like 'work'}, {Slice => {}})->[0]->{max};

    return $self->render(json => {result => 'ok', max_price => $max_price,});
}

sub photo_upload {
    my $self = shift;

    if (my $file = $self->param('file')) {
        my $path = '/var/data/storage/zavrus/photos/';
        my $name = Time::HiRes::time =~ s/\.//r; # Unique name

        $file->move_to($path.'/'.$name.'.jpg');

        my $photo_url = 'http://tstorage.rplusmgmt.com/zavrus/photos/' . $name . '.jpg';

        return $self->render(json => {result => 'ok', photo_url => $photo_url});

    } else {
        return $self->render(json => {result => 'fail'});
    }
}

sub remove {
    my $self = shift;

    my $realty_id = $self->param('realty_id');
    my $code = $self->param('code');

    #my $realty_code = Rplus::Model::RealtyCodesExt::Manager->get_objects(
    #    query => [
    #        realty_id => $realty_id,
    #        code => $code,
    #    ])->[0];

	return $self->render(json => {result => 'fail', reason => 'record_not_found'});

    #return $self->render(json => {result => 'fail', reason => 'record_not_found'}) unless $realty_code;

    my $realty = Rplus::Model::Realty::Manager->get_objects(
        query => [
            id => $realty_id,
        ])->[0];
    return $self->render(json => {result => 'fail', reason => 'realty_not_found'}) unless $realty;

    $realty->state_code('work');
    $realty->work_info($realty->work_info . ' -УДАЛЕНО ПОЛЬЗОВАТЕЛЕМ-');
    $realty->save(changes_only => 1);

    return $self->render(json => {result => 'ok'});
}

sub add {
    my $self = shift;

    my $offer_type_code = 'rent';
    my $state_code = 'work';
    my $type_code = $self->param('type_code');

    my $rooms_count = $self->param('rooms_count') || undef;
    my $floor = $self->param('floor') || undef;
    my $floors_count = $self->param('floors_count') || undef;
    my $price = $self->param('price') || undef;

    my $work_info = $self->param('specs');
    my $description = $self->param('description');

    my $zavrus_id = 16;

    my $owner_phones_str = $self->param('owner_phones_str');
    unless ($owner_phones_str) {
        return $self->render(json => {result => 'fail', reason => 'no_phone'});
    }

    $work_info .= ' ТЕЛЕФОН: ' . $owner_phones_str;

    my @photos = $self->param('photos[]');

    my $realty = Rplus::Model::Realty->new(
        type_code => $type_code,
        offer_type_code => $offer_type_code,
        state_code => $state_code,
        source_media_id => $zavrus_id,

        rooms_count => $rooms_count,
        floor => $floor,
        floors_count => $floors_count,

        owner_price => $price,
        owner_phones => ['4212000000'],

        work_info => $work_info,
        description => $description,
		account_id => 4,
    )->save;

    foreach (@photos) {
        my $photo = Rplus::Model::Photo->new;
        $photo->realty_id($realty->id);
        $photo->filename($_);
        $photo->thumbnail_filename($_);
        $photo->save;
    }

    my $code = _generate_code(6);

    #my $realty_code = Rplus::Model::RealtyCodesExt->new(
    #    realty_id => $realty->id,
    #    code => $code,
    #);
    #$realty_code->save;

    return $self->render(json => {result => 'ok', realty_id => $realty->id, realty_code => $code});
}

1;
