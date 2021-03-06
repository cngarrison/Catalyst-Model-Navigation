package Catalyst::Model::Navigation;
# ABSTRACT: Create HTML::Navigation model, populate with action attributes, CMS pages, and app config

use v5.16;
use Moose;
# use MooseX::ClassAttribute;
use namespace::autoclean;

# extends "Catalyst::Model::Adaptor";
# extends "Catalyst::Model::Factory::PerRequest";
extends "Catalyst::Model::Factory";

use Scalar::Util qw(weaken blessed);
use URL::Encode qw(url_params_each);
use Data::Printer;
use Catalyst::Utils;

our $VERSION = 'v0.0.12';

has "action_menu_items_for_site" => (
	is      => "rw",
	isa     => "HashRef",
	traits  => ['Hash'],
	default => sub { {} }, #hashref; keys are site codes
	handles => {
		get_action_menu_item_for_site      => 'get',
		get_all_action_menu_items_for_site => 'values',
		set_action_menu_item_for_site      => 'set',
		has_action_menu_items_for_site     => 'count',
		has_no_action_menu_items_for_site  => 'is_empty',
		clear_action_menu_items_for_site   => 'clear',
	},
);
has "action_menu_items" => (
	is      => "rw",
	isa     => "HashRef",
	traits  => ['Hash'],
	default => sub { {} },
	handles => {
		get_action_menu_item      => 'get',
		get_all_action_menu_items => 'values',
		set_action_menu_item      => 'set',
		has_action_menu_items     => 'count',
		has_no_action_menu_items  => 'is_empty',
		clear_action_menu_items   => 'clear',
	},
);
has "cms_menu_items" => (
	is      => "rw",
	isa     => "HashRef",
	traits  => ['Hash'],
	default => sub { {} },
	handles => {
		get_cms_menu_item       => 'get',
		get_all_cms_menu_items  => 'values',
		get_cms_menu_items_list => 'elements',
		set_cms_menu_item       => 'set',
		has_cms_menu_items      => 'count',
		has_no_cms_menu_items   => 'is_empty',
		clear_cms_menu_items    => 'clear',
	},
);

has "menus" => (
	is      => "rw",
	isa     => "HashRef[HashRef]",
	traits  => ['Hash'],
	default => sub { {} },
	handles => {
		get_menu       => 'get',
		get_menu_paths => 'keys',
		get_all_menus  => 'values',
		set_menus      => 'set',
		has_menus      => 'count',
		has_no_menus   => 'is_empty',
		clear_menus    => 'clear',
	},
);

has "default_category" => (
	is      => 'rw',
	isa     => 'Str',
	default => 'default',
);

has 'debug_nav' => (
	is      => 'rw',
	isa     => 'Bool',
	traits  => ['Bool'],
	default => 0,
	handles => {
		enable_debug_nav  => 'set',
		disable_debug_nav => 'unset',
	},
);


__PACKAGE__->config(
	class => "HTML::Navigation",
	default_category => 'info',
	args  => {
		no_sorting => 0,
	},
);


sub prepare_arguments {
# 	my ($self, $app) = @_; # $app sometimes written as $c
# 	my ( $self, $c ) = @_;    # $better written as $c for Factory::PerRequest
	my $self = shift;
	my $c    = shift;
	my $args = $self->next::method( $c, @_ );

	$self->enable_debug_nav if $c->debug || Catalyst::Utils::env_value( $c->catapp_name, 'DEBUG_NAVIGATION' );

#  	$c->log->debug( "Preparing ARGUMENTS with: " . p($args) ) if $self->debug_nav;

	$self->_build_cms_menu_items($c);    ## can't use a lazy builder, need to get $ctx
	$self->_build_action_menu_items($c); ## can't use a lazy builder, need to get $ctx

	## Root of menus is #; a menu_item with parent of # will be located directly on the menu bar (for traditional menu bars)
	##   MenuBar#MenuLabel#SubMenuLabel  -vs-  #MenuLabel#SubMenuLabel (default menu bar)
	## menu_name: Members, AdminHome, RecordEdit, Developer, Footer (is generally name of a menubar, but could be a submenu)
	my $menu_name = delete $args->{menu_name};
	$menu_name ||= '';
	$c->log->debug("Preparing ARGUMENTS for menu $menu_name") if $self->debug_nav;

	return {
		%{$args},
		items => $self->action_items_for_menu( $c, $menu_name ),
# 		items => $self->cms_items($c, $menu_name),
	};
} ## end sub prepare_arguments


sub _build_action_menu_items {
	my $self = shift;
	my $c    = shift;

	my $site_code = $c->site_code;

	if (my $ami = $self->get_action_menu_item_for_site($site_code)) {
		$c->log->debug("Using NAV ACTION ITEMS for $site_code") if $self->debug_nav;
		$self->action_menu_items( $ami );
	} else {
# 	if ( $self->has_no_action_menu_items ) {
		$self->clear_action_menu_items;
		$c->log->debug("Creating NAV ACTION ITEMS") if $self->debug_nav;
		my $dispatcher = $c->dispatcher;

		foreach my $c_name ( $c->controllers(qr//) ) {
			my $controller        = $c->controller($c_name);
			my @action_containers = $dispatcher->get_containers( $controller->action_namespace($c) );
			$c->log->debug("Looking at Controller $c_name for navigation entries") if $self->debug_nav;

# 			$c->log->debug( "Value of action_containers is: " . p(@action_containers) ) if $self->debug_nav;
			my $action_container = $action_containers[-1];       # get end of chain
			my $actions          = $action_container->actions;
# 			$c->log->debug( "Value of actions for last action_container is: " . p($actions) ) if $self->debug_nav;
			foreach my $key ( keys(%$actions) ) {
				my $action = $actions->{$key};
# 					my $chained = $action->can('chain') ? $action->chain : [$action];
# 					if ( my @menu_actions = grep { $_->attributes->{Menu} } @$chained ) { # reverse @$chained ???
# 			$c->log->debug( "Value of action is: " . $menu_actions[0]->namespace ) if $self->debug_nav;
# 						$self->add_action_menu_item( $c, $menu_actions[0], $controller );
# 					}
				if ( $action->attributes->{Menu} ) {
					$self->add_action_menu_item( $c, $action, $controller );
				}

			} ## end foreach my $key ( keys(%$actions) )

		} ## end foreach my $c_name ( $c->controllers(...))

		$c->log->debug("Setting NAV ACTION ITEMS for $site_code") if $self->debug_nav;
		$self->set_action_menu_item_for_site($site_code, $self->action_menu_items);
	} ## end if ( $self->has_no_action_menu_items)

# 	my $action_menu_items = $self->action_menu_items;
#  	$c->log->debug( "Value of action_menu_items is: " . p($action_menu_items) ) if $self->debug_nav;
# 	my $menus = $self->menus;
#  	$c->log->debug( "Value of menus is: " . p($menus) ) if $self->debug_nav;

} ## end sub _build_action_menu_items

sub _build_cms_menu_items {
	my $self = shift;
	my $c    = shift;

	$self->clear_cms_menu_items;
# 	if ( $self->has_no_cms_menu_items ) {
		$c->log->debug("Creating NAV CMS ITEMS") if $self->debug_nav;
		my $pages = $c->model('DBIC::PageTemplate')->published_pages;

		while (my $page = $pages->next) {
# 			$c->log->debug("Looking at Page ".$page->name." for cms entries") if $self->debug_nav;
			$self->add_cms_menu_item( $c, $page );
		}
# 	}

# 	my $cms_menu_items = $self->cms_menu_items;
#  	$c->log->debug( "Value of cms_menu_items is: " . p($cms_menu_items) ) if $self->debug_nav;
# 	my $menus = $self->menus;
#  	$c->log->debug( "Value of menus is: " . p($menus) ) if $self->debug_nav;

} ## end sub _build_cms_menu_items

sub action_items_for_menu {
	my $self      = shift;
	my $c         = shift;
	my $menu_name = shift;

	my @am_items = sort { $a->{menu_parent} cmp $b->{menu_parent} }
	  grep { $_->{menu_parent} =~ m/^$menu_name(#.*)?$/ } (
		$self->get_all_action_menu_items,
		$self->get_all_cms_menu_items,
		$c->get_all_extra_navigation_items
	  );

#  	$c->log->debug( "Value of extra_navigation_items is: " . p($c->get_all_extra_navigation_items) ) if $self->debug_nav;
#  	$c->log->debug( "Searching for am_items with parent matching: m/^$menu_name(#.*)?\$/" ) if $self->debug_nav;
#  	$c->log->debug( "Value of am_items is: " . p(@am_items) ) if $self->debug_nav; # && $menu_name eq 'AdminRecordbar';

	my $current_action_key = $c->action->namespace . '/' . $c->action->name;

	my @nav_items;
	foreach my $am_item (@am_items) {
		my $m_parent = $am_item->{menu_parent};
# 		$m_parent =~ s/^([^#]*)(#.*)/$2/; ## remove name of menubar
		$m_parent =~ s/^$menu_name(#.*)/$1/; ## remove name of menubar#menu

		my $is_active =
		  ( $am_item->{path} eq $current_action_key ||
		    ( $current_action_key eq '/docs' && $c->stash->{page}->{path} eq $am_item->{path} )
		  ) ? 1 : 0;
		$am_item->{is_active} = $is_active;    # we're changing $am_item each time, should we be making a copy instead?
#  		$c->log->debug( "$am_item->{path} active: $is_active for action_key: $current_action_key" ) if $self->debug_nav;

		my @sub_menus = split( '#', $m_parent );
		shift @sub_menus unless $sub_menus[0];
#  		$c->log->debug( "Use $m_parent to split sub_menus: " . p(@sub_menus) ) if $self->debug_nav;

		my $last_menu;
		if ( scalar @sub_menus >= 1 ) {        # count of items, not last index
			my $multi_nav_items = \@nav_items;    # grab copy of 'root level' menu nav items
#  			$c->log->debug( "Have menu(s) to add for $m_parent, to existing multi_nav_items: " . p($multi_nav_items) ) if $self->debug_nav;
			my $parent_menu;
			for ( my $i = 0; $i <= $#sub_menus; $i++ ) {

				my $menu_path_item = $sub_menus[$i];

#  				$c->log->debug( "Searching multi_nav_items for: " . $menu_path_item ) if $self->debug_nav;
				my ($nav_item) = grep { $_->{path} eq $menu_path_item && defined $_->{children} } @$multi_nav_items;
				if ( !$nav_item ) {

					my $menu_path = '#' . join( '#', @sub_menus[0 .. $i] );
					my $mp = $menu_name . $menu_path;
# 					$c->log->debug( "Value of mp is: " . $mp ) if $self->debug_nav;

# 					$c->log->debug( "Creating new sub_menu for: " . $am_item->{menu_parent} . " using path: " . $menu_path_item ) if $self->debug_nav;
# 					my $menu = $self->get_menu( $am_item->{menu_parent} );
					my $menu = $self->get_menu($mp);
					$nav_item = {
						path        => $menu_path_item,
						order       => $menu->{order},
						label       => $menu->{label},         # || $menu_path_item,
						title       => $menu->{title},
						icon        => $menu->{icon},
						category    => $menu->{category},
						description => $menu->{description},
						css_classes => $menu->{css_classes},
						dom_id      => $menu->{dom_id},
						children    => [],
					};

					push( @$multi_nav_items, $nav_item );
#  					$c->log->debug( "Added new sub_menu for: " . p($nav_item) . " to multi_nav_items: " . p($multi_nav_items) ) if $self->debug_nav;
				} ## end if ( !$nav_item )

				$last_menu = $parent_menu = $nav_item;
				$multi_nav_items = $nav_item->{children};    # grab copy of 'current level' menu nav items
			} ## end for ( my $i = 0; $i <= $#sub_menus...)

			push( @{ $last_menu->{children} }, $am_item );

#  			$c->log->debug( "Pushed: " . $am_item->{menu_parent} . " with path: " . $last_menu->{path} . " to multi_nav_items: " . p( $last_menu->{children} ) ) if $self->debug_nav;
		} else {
			## top-level link, no menu
			push( @nav_items, $am_item );

		}
	} ## end foreach my $am_item (@am_items)

#  	$c->log->debug( "Value of nav_items is: " . p(@nav_items) ) if $self->debug_nav;

	return [@nav_items];
} ## end sub action_items_for_menu



# Create the items needed to build the HTML::Navigation object.
sub add_action_menu_item {
	my ( $self, $c, $action, $controller ) = @_;

	my $menu_parents =
	  defined $action->attributes->{MenuParent} && scalar @{ $action->attributes->{MenuParent} } > 0
	  ? $action->attributes->{MenuParent}
	  : ['#'];

# 	$c->log->debug( sprintf( "Action details: \nclass: %s\nnamespace: %s\nreverse: %s\nprivate_path: %s", $action->class, $action->namespace, $action->reverse, $action->private_path ) ) if $self->debug_nav;
#  	$c->log->debug( "Value of menu_parents is: " . p($menu_parents) ) if $self->debug_nav;

# 	my $c_nav_config   = $c->config->{navigation}          || {};
# 	my $ctr_nav_config = $controller->config->{navigation} || {};

	my $action_key = $action->namespace . '/' . $action->name;
# 	$c->log->debug( sprintf( "Adding action item for path: %s with parent: %s in controller: %s", $action_key, $action->attributes->{MenuParent}->[0] || '', ref $controller ) ) if $self->debug_nav;

	my $last_item = {};
	my $last_item_name = '';
	for ( my $i = 0; $i <= $#$menu_parents; $i++ ) {
		my $parent_mp = $menu_parents->[$i];
		## does parent contain a hash
		## if not, it's the name of a menubar, so append # to make menu root
		$parent_mp = $parent_mp . '#' unless $parent_mp =~ /#/;
		my $act_attrs = $action->attributes;

		my $item_name = $act_attrs->{Menu}->[$i] // $last_item_name;
		$last_item_name = $item_name;
		my $mp_ak = sprintf( '%s!%s!%s', $parent_mp, $item_name, $action_key );

		next if $self->get_action_menu_item($mp_ak);

		my $c_nav_item   = $c->get_navigation_item($mp_ak) || {};
		my $ctr_nav_item = $controller->get_navigation_item($mp_ak) || {};


		my $conditions         = $c_nav_item->{conditions}             // $ctr_nav_item->{conditions}             // $act_attrs->{MenuCond}      // [];
		my $action_cond_args   = $c_nav_item->{condition_args}         // $ctr_nav_item->{condition_args}         // $act_attrs->{MenuCondArgs}  // [];
		my $action_cond_params = $c_nav_item->{condition_query_params} // $ctr_nav_item->{condition_query_params} // $act_attrs->{MenuCondQueryParams}->[$i] // $last_item->{condition_query_params} // '';
		$conditions = [map { $self->_build_condition_coderef( $_, $action_cond_args, $action_cond_params ) } @$conditions]
		  if ( scalar @$action_cond_args >= 1 || $action_cond_params );

# 		if ( scalar @$conditions == 0 ) {
			my $role_attr = $act_attrs->{MenuRoles}->[$i] // $last_item->{required_roles} // '';
			if ($role_attr) {
				my @roles_and = split( ',', $role_attr );
				# Check each required role.
				foreach my $role (@roles_and) {
					push(
						@$conditions,
						sub {
							my $ctx = shift;
							return undef unless $ctx;
							if ( $ctx->can('check_user_roles') ) {
								if ( $role =~ /\|/ ) {
									my @roles = split( /\|/, $role );
									return $ctx->check_any_user_role(@roles) ? 1 : 0;
								} else {
									return $ctx->check_user_roles($role) ? 1 : 0;
								}
							} ## end if ( $ctx->can('check_user_roles'...))
						}
					);
				} ## end foreach my $role (@roles_and)
			} ## end if ($role_attr)
# 		} ## end if ( scalar @$conditions == 0 )

		my $action_args   = $act_attrs->{MenuUrlArgs} // [];
		my $action_url_params = $c_nav_item->{url_query_params}  // $ctr_nav_item->{url_query_params}  // $act_attrs->{MenuUrlQueryParams}->[$i] // $last_item->{url_query_params}  // '',
		my $url;
		my $url_cb;
		if ( scalar @$action_args >= 1 || $action_url_params  ) {
			$url_cb = $self->_build_url_coderef( $action, $action_args, $action_url_params );
		} else {
# 			$url = $c->uri_for_action($action);
			## if we call $c->uri_for_action($action) now, then we get BASE for url of whatever app was first called with
			## eg. could be venuefinder.net.au rather than venuefinder.com.au, needs to be BASE from current request
			$url_cb = $self->_build_url_coderef( $action, [], {} );
		}

		## when finding the value to use for each of the item options; default values start with action attributes
		## set either inline or via action config; values are overridden by upper layers of the app; next is
		## controller's config->{navigation}, followed by app's config->{navigation}; lastly, use values from
		## item of previous menu_parent. The first defined value found will be used:
		## - $myapp->config->{navigation} (also $c)
		## - $self->config->{navigation} (also $controller)
		## - $action->{attributes}
		## - $last_item

		my $item = {
			menu_parent => $parent_mp,
			path        => $action_key,
			(
				$url_cb
				? ( url_cb => $url_cb )
				: ( url    => $url )
			),
			query_params   => $action_url_params,
			order          => $c_nav_item->{order}          // $ctr_nav_item->{order}          // $act_attrs->{MenuOrder}->[$i]                                // $last_item->{order}          // 0,
			label          => $c_nav_item->{label}          // $ctr_nav_item->{label}          // $act_attrs->{MenuLabel}->[$i]   // $act_attrs->{Menu}->[$i]  // $last_item->{label}          // '',
			title          => $c_nav_item->{title}          // $ctr_nav_item->{title}          // $act_attrs->{MenuTitle}->[$i]                                // $last_item->{title}          // '',
			icon           => $c_nav_item->{icon}           // $ctr_nav_item->{icon}           // $act_attrs->{MenuIcon}->[$i]                                 // $last_item->{icon}           // '',
			dom_id         => $c_nav_item->{dom_id}         // $ctr_nav_item->{dom_id}         // $act_attrs->{MenuDomId}->[$i]                                // $last_item->{dom_id}         // '',
			css_classes    => $c_nav_item->{css_classes}    // $ctr_nav_item->{css_classes}    // $act_attrs->{MenuCssClasses}                                 // [],
			category       => $c_nav_item->{category}       // $ctr_nav_item->{category}       // $act_attrs->{MenuCategory}->[$i]                             // $last_item->{category}       // $self->default_category,
			description    => $c_nav_item->{description}    // $ctr_nav_item->{description}    // $act_attrs->{MenuDescription}->[$i]                          // $last_item->{description}    // '',
			required_roles => $c_nav_item->{required_roles} // $ctr_nav_item->{required_roles} // $act_attrs->{MenuRoles}->[$i]                                // $last_item->{required_roles} // '',
			conditions     => $conditions,
		};

		$last_item = $item;
		$self->set_action_menu_item( $mp_ak, $item );


		my $m_parent = $parent_mp;
		$m_parent =~ s/^([^#]*)(#.*)/$2/; ## remove name of menubar
		my $menubar = $1 || '';
		my @sub_menus = split( '#', $m_parent );
		shift @sub_menus unless $sub_menus[0];

		while ( scalar @sub_menus >= 1 ) {    # count of items, not last index
			my $menu_path_item = $sub_menus[-1];
			my $menu_path = '#' . join( '#', @sub_menus );
# 			$c->log->debug( "Checking menu exists: " . $menu_path ) if $self->debug_nav;

			my $mp = $menubar . $menu_path;
			if ( $mp && !$self->get_menu($mp) ) {
# 				$c->log->debug( "Setting menu - menu_path is: " . $menu_path ) if $self->debug_nav;
				my $c_nav_item_menu   = $c->get_navigation_item($mp)          || {};
				my $ctr_nav_item_menu = $controller->get_navigation_item($mp) || {};
				my $nav_menu = $c->model('DBIC::NavMenu')->hri->find({path=>$mp}) || {};
				$c->log->debug(
					sprintf(
						"Setting menu %s with label - ctx: %s, ctrl: %s, attr: %s, path: %s",
						$mp,
						$nav_menu->{label} || $c_nav_item_menu->{label} || '', $ctr_nav_item_menu->{label} || '',
						$act_attrs->{MenuParentLabel}->[0] || '', $menu_path_item
					)
				) if $self->debug_nav;
				$self->set_menus(
					$mp, {
						path        => $nav_menu->{path}        // $c_nav_item_menu->{path}        // $ctr_nav_item_menu->{path}        // $act_attrs->{MenuParentPath}->[0]        // $menu_path,
						order       => $nav_menu->{sort_order}  // $c_nav_item_menu->{order}       // $ctr_nav_item_menu->{order}       // $act_attrs->{MenuParentOrder}->[0]       // 0,
						label       => $nav_menu->{label}       // $c_nav_item_menu->{label}       // $ctr_nav_item_menu->{label}       // $act_attrs->{MenuParentLabel}->[0]       // $menu_path_item,
						title       => $nav_menu->{title}       // $c_nav_item_menu->{title}       // $ctr_nav_item_menu->{title}       // $act_attrs->{MenuParentTitle}->[0]       // '',
						icon        => $nav_menu->{icon}        // $c_nav_item_menu->{icon}        // $ctr_nav_item_menu->{icon}        // $act_attrs->{MenuParentIcon}->[0]        // '',
						category    => $nav_menu->{category}    // $c_nav_item_menu->{category}    // $ctr_nav_item_menu->{category}    // $act_attrs->{MenuParentCategory}->[0]    // $self->default_category,
						description => $nav_menu->{description} // $c_nav_item_menu->{description} // $ctr_nav_item_menu->{description} // $act_attrs->{MenuParentDescription}->[0] // '',
						dom_id      => $nav_menu->{dom_id}      // $c_nav_item_menu->{dom_id}      // $ctr_nav_item_menu->{dom_id}      // $act_attrs->{MenuParentDomId}->[0]       // '',
						css_classes => $nav_menu->{css_classes} // $c_nav_item_menu->{css_classes} // $ctr_nav_item_menu->{css_classes} // $act_attrs->{MenuParentCssClasses}       // [],
					}
				);
			} ## end if ( $menu_path && !$self->get_menu...)
			pop @sub_menus;

		} ## end while ( scalar @sub_menus >= 1 )


	} ## end for ( my $i = 0; $i <= $#$menu_parents...)
} ## end sub add_action_menu_item

sub add_cms_menu_item {
	my ( $self, $c, $page ) = @_;

	my $parent_mp = $page->menu_parent || '#';

	## does parent contain a hash
	## if not, it's the name of a menubar, so append # to make menu root
	$parent_mp = $parent_mp . '#' unless $parent_mp =~ /#/;

	my $mp_tp = sprintf( '%s!%s', $parent_mp, $page->template_path );

	return if $self->get_cms_menu_item($mp_tp);

	my $item = {
		menu_parent    => $parent_mp,
		path           => $page->template_path,
# 		path           => '/docs/' . $page->template_path,
		url            => $c->uri_for_action( '/docs', $page->template_path ),
		order          => $page->menu_order // 0,
		label          => $page->menu_label // $page->name // '',
		title          => $page->menu_title // $page->menu_label // $page->name // '',
		icon           => $page->menu_icon // '',
		dom_id         => '',
		css_classes    => $page->menu_css_classes // [],
		category       => $page->menu_category // $self->default_category,
		description    => $page->description // '',
		required_roles => '',
# 		conditions     => $conditions,
	};

	$self->set_cms_menu_item( $mp_tp, $item );

	my $m_parent = $parent_mp;
	$m_parent =~ s/^([^#]*)(#.*)/$2/; ## remove name of menubar
	my $menubar = $1 || '';
	my @sub_menus = split( '#', $m_parent );
	shift @sub_menus unless $sub_menus[0];

	while ( scalar @sub_menus >= 1 ) {    # count of items, not last index
		my $menu_path_item = $sub_menus[-1];
		my $menu_path = '#' . join( '#', @sub_menus );
# 			$c->log->debug( "Checking menu exists: " . $menu_path ) if $self->debug_nav;

		my $mp = $menubar . $menu_path;
# 		if ( $mp && !$self->get_menu($mp) ) {
		if ( $mp ) {
# 				$c->log->debug( "Setting menu - menu_path is: " . $menu_path ) if $self->debug_nav;
			my $c_nav_item_menu = $c->get_navigation_item($mp) || {};
			my $nav_menu = $c->model('DBIC::NavMenu')->hri->find({path=>$mp}) || {};
			$c->log->debug(
				sprintf(
					"Setting menu %s with label - ctx: %s, path: %s",
					$mp,
					$nav_menu->{label} || $c_nav_item_menu->{label} || '',
					$menu_path_item
				)
			) if $self->debug_nav;
			$self->set_menus(
				$mp, {
					path        => $nav_menu->{path}        // $c_nav_item_menu->{path}        // $menu_path,
					order       => $nav_menu->{sort_order}  // $c_nav_item_menu->{order}       // 0,
					label       => $nav_menu->{label}       // $c_nav_item_menu->{label}       // $menu_path_item,
					title       => $nav_menu->{title}       // $c_nav_item_menu->{title}       // '',
					icon        => $nav_menu->{icon}        // $c_nav_item_menu->{icon}        // '',
					category    => $nav_menu->{category}    // $c_nav_item_menu->{category}    // $self->default_category,
					description => $nav_menu->{description} // $c_nav_item_menu->{description} // '',
					dom_id      => $nav_menu->{dom_id}      // $c_nav_item_menu->{dom_id}      // '',
					css_classes => $nav_menu->{css_classes} // $c_nav_item_menu->{css_classes} // [],
				}
			);
		} ## end if ( $mp && !$self->get_menu($mp...))
		pop @sub_menus;

	} ## end while ( scalar @sub_menus >= 1 )

} ## end sub add_cms_menu_item



# gets used as class method from CNG::Roles::Navigation
sub _build_url_coderef {
	my ( $self, $action, $action_args, $url_query_params ) = @_;
	my $sub = sub {
		my $ctx = shift;

		my $processed_action_args  = [];
		my $processed_url_query_params = {};

		my $varname2val = sub {
			my $varname = shift;

			my @elems = split( '\.', $varname );
			my $elem1 = shift @elems;
			my $val;
			if ( $ctx->can($elem1) ) {
				$val = $ctx->$elem1;
			} elsif ( exists $ctx->stash->{$elem1} ) {
				$val = $ctx->stash->{$elem1};
			} else {
				$val = $elem1;
			}
			foreach my $elem (@elems) { # process nested elements of var name
				if ( blessed $val && $val->can($elem) ) {
					$val = $val->$elem;
				} elsif ( exists $ctx->stash->{$elem} ) {
					$val = $ctx->stash->{$elem};
				} elsif ( ref $val eq 'HASH' && exists $val->{$elem} ) {
					$val = $val->{$elem};
				} else {
					$val = $elem;
				}
			} ## end foreach my $elem (@elems)

			return $val;
		};

		@$processed_action_args = map {
			$varname2val->($_)
		} @$action_args; # list of varnames to convert to values

		$url_query_params //= {};
		if (ref $url_query_params eq 'HASH') {
			$processed_url_query_params = $url_query_params;
		} elsif (! ref $url_query_params) { # must be a string
			my $process_url_query_params_cb = sub {
				my ($name, $varname) = @_;
				$processed_url_query_params->{$name} = $varname2val->($varname);
			};
			url_params_each($url_query_params, $process_url_query_params_cb); # query string of queryarg=varnames to convert to hash of values
		} else {
			warn sprintf("url_query_params is something unexpected for action %s: with params: %s\n", "$action", p($url_query_params));
		}

		my $uri = $ctx->uri_for_action( $action, $processed_action_args, $processed_url_query_params );
		return $uri;
	};
	return $sub;
} ## end sub _build_url_coderef


sub _build_condition_coderef {
	my ( $self, $cond_cb, $cond_args, $cond_query_params ) = @_;
	my $sub = sub {
		my $ctx = shift;

		my $processed_cond_args  = [];
		my $processed_cond_query_params = {};

		my $varname2val = sub {
			my $varname = shift;

			my @elems = split( '\.', $varname );
			my $elem1 = shift @elems;
			my $val;
			if ( $ctx->can($elem1) ) {
				$val = $ctx->$elem1;
			} elsif ( exists $ctx->stash->{$elem1} ) {
				$val = $ctx->stash->{$elem1};
			} else {
				$val = $elem1;
			}
			foreach my $elem (@elems) { # process nested elements of var name
				if ( blessed $val && $val->can($elem) ) {
					$val = $val->$elem;
				} elsif ( exists $ctx->stash->{$elem} ) {
					$val = $ctx->stash->{$elem};
				} elsif ( ref $val eq 'HASH' && exists $val->{$elem} ) {
					$val = $val->{$elem};
				} else {
					$val = $elem;
				}
			} ## end foreach my $elem (@elems)

			return $val;
		};

		@$processed_cond_args = map {
			$varname2val->($_)
		} @$cond_args; # list of varnames to convert to values

		$cond_query_params //= {};
		if (ref $cond_query_params eq 'HASH') {
			$processed_cond_query_params = $cond_query_params;
		} elsif (! ref $cond_query_params) { # must be a string
			my $process_cond_query_params_cb = sub {
				my ($name, $varname) = @_;
				$processed_cond_query_params->{$name} = $varname2val->($varname);
			};
			url_params_each($cond_query_params, $process_cond_query_params_cb); # query string of queryarg=varnames to convert to hash of values
		} else {
			warn sprintf("cond_query_params is something unexpected for cond with params: %s\n", p($cond_query_params));
		}

		return $cond_cb->( $ctx, $processed_cond_args, $processed_cond_query_params );
	};
	return $sub;
} ## end sub _build_condition_coderef

__PACKAGE__->meta->make_immutable;


1;

