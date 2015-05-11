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

# VERSION: generated by DZP::OurPkgVersion

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
#  	$c->log->debug( "Preparing ARGUMENTS with: " . p($args) ) if $c->debug;

	$self->_build_action_menu_items($c);    # can't use a lazy builder, need to get $ctx

	## Root of menus is #; a menu_item with parent of # will be located directly on the menu bar (for traditional menu bars)
	##  MenuBar#MenuLabel#SubMenuLabel  -vs-  #MenuLabel#SubMenuLabel (default menu bar)
	my $menu_name = delete $args->{menu_name};    # Members, Admin, Developer, Footer
	$menu_name ||= '';
	$c->log->debug("Preparing ARGUMENTS for menu $menu_name") if $c->debug;

	return {
		%{$args},
		items => $self->action_items_for_menu( $c, $menu_name ),
# 		items => $self->cms_items($c, $menu_name),
	};
} ## end sub prepare_arguments


sub _build_action_menu_items {
	my $self = shift;
	my $c    = shift;

	if ( $self->has_no_action_menu_items ) {
		$c->log->debug("Creating NAV ITEMS") if $c->debug;
		my $dispatcher = $c->dispatcher;

		foreach my $c_name ( $c->controllers(qr//) ) {
			my $controller        = $c->controller($c_name);
			my @action_containers = $dispatcher->get_containers( $controller->action_namespace($c) );
			$c->log->debug("Looking at Controller $c_name for navigation entries") if $c->debug;

# 			$c->log->debug( "Value of action_containers is: " . p(@action_containers) ) if $c->debug;
			my $action_container = $action_containers[-1];       # get end of chain
			my $actions          = $action_container->actions;
# 			$c->log->debug( "Value of actions for last action_container is: " . p($actions) ) if $c->debug;
			foreach my $key ( keys(%$actions) ) {
				my $action = $actions->{$key};
# 					my $chained = $action->can('chain') ? $action->chain : [$action];
# 					if ( my @menu_actions = grep { $_->attributes->{Menu} } @$chained ) { # reverse @$chained ???
# 			$c->log->debug( "Value of action is: " . $menu_actions[0]->namespace ) if $c->debug;
# 						$self->add_action_menu_item( $c, $menu_actions[0], $controller );
# 					}
				if ( $action->attributes->{Menu} ) {
					$self->add_action_menu_item( $c, $action, $controller );
				}

			} ## end foreach my $key ( keys(%$actions) )

		} ## end foreach my $c_name ( $c->controllers(...))
	} ## end if ( $self->has_no_action_menu_items)

# 	my $action_menu_items = $self->action_menu_items;
#  	$c->log->debug( "Value of action_menu_items is: " . p($action_menu_items) ) if $c->debug;
# 	my $menus = $self->menus;
#  	$c->log->debug( "Value of menus is: " . p($menus) ) if $c->debug;

} ## end sub _build_action_menu_items

sub action_items_for_menu {
	my $self      = shift;
	my $c         = shift;
	my $menu_name = shift;

	my @am_items = sort { $a->{menu_parent} cmp $b->{menu_parent} }
	  grep { $_->{menu_parent} =~ m/^$menu_name(#.*)?$/ } ($self->get_all_action_menu_items, $c->get_all_extra_navigation_items);

#  	$c->log->debug( "Value of extra_navigation_items is: " . p($c->get_all_extra_navigation_items) ) if $c->debug;
#  	$c->log->debug( "Searching for am_items with parent matching: m/^$menu_name(#.*)?\$/" ) if $c->debug;
#  	$c->log->debug( "Value of am_items is: " . p(@am_items) ) if $c->debug; # && $menu_name eq 'AdminRecordbar';

	my $current_action_key = $c->action->namespace . '/' . $c->action->name;

	my @nav_items;
	foreach my $am_item (@am_items) {
		my $m_parent = $am_item->{menu_parent};
# 		$m_parent =~ s/^([^#]*)(#.*)/$2/; ## remove name of menubar
		$m_parent =~ s/^$menu_name(#.*)/$1/; ## remove name of menubar#menu

		my $is_active = $am_item->{path} eq $current_action_key ? 1 : 0;
		$am_item->{is_active} = $is_active;    # we're changing $am_item each time, should we be making a copy instead?
#  		$c->log->debug( "$am_item->{path} active: $is_active" ) if $c->debug;

		my @sub_menus = split( '#', $m_parent );
		shift @sub_menus unless $sub_menus[0];
#  		$c->log->debug( "Use $m_parent to split sub_menus: " . p(@sub_menus) ) if $c->debug;

		my $last_menu;
		if ( scalar @sub_menus >= 1 ) {        # count of items, not last index
			my $multi_nav_items = \@nav_items;    # grab copy of 'root level' menu nav items
#  			$c->log->debug( "Have menu(s) to add for $m_parent, to existing multi_nav_items: " . p($multi_nav_items) ) if $c->debug;
			my $parent_menu;
			for ( my $i = 0; $i <= $#sub_menus; $i++ ) {

				my $menu_path_item = $sub_menus[$i];

#  				$c->log->debug( "Searching multi_nav_items for: " . $menu_path_item ) if $c->debug;
				my ($nav_item) = grep { $_->{path} eq $menu_path_item && defined $_->{children} } @$multi_nav_items;
				if ( !$nav_item ) {

					my $menu_path = '#' . join( '#', @sub_menus[0 .. $i] );
					my $mp = $menu_name . $menu_path;
# 					$c->log->debug( "Value of mp is: " . $mp ) if $c->debug;

# 					$c->log->debug( "Creating new sub_menu for: " . $am_item->{menu_parent} . " using path: " . $menu_path_item ) if $c->debug;
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
#  					$c->log->debug( "Added new sub_menu for: " . p($nav_item) . " to multi_nav_items: " . p($multi_nav_items) ) if $c->debug;
				} ## end if ( !$nav_item )

				$last_menu = $parent_menu = $nav_item;
				$multi_nav_items = $nav_item->{children};    # grab copy of 'current level' menu nav items
			} ## end for ( my $i = 0; $i <= $#sub_menus...)

			push( @{ $last_menu->{children} }, $am_item );

#  			$c->log->debug( "Pushed: " . $am_item->{menu_parent} . " with path: " . $last_menu->{path} . " to multi_nav_items: " . p( $last_menu->{children} ) ) if $c->debug;
		} else {
			## top-level link, no menu
			push( @nav_items, $am_item );

		}
	} ## end foreach my $am_item (@am_items)

#  	$c->log->debug( "Value of nav_items is: " . p(@nav_items) ) if $c->debug;

	return [@nav_items];
} ## end sub action_items_for_menu



# Create the items needed to build the HTML::Navigation object.
sub add_action_menu_item {
	my ( $self, $c, $action, $controller ) = @_;

	my $menu_parents =
	  defined $action->attributes->{MenuParent} && scalar @{ $action->attributes->{MenuParent} } > 0
	  ? $action->attributes->{MenuParent}
	  : ['#'];

# 	$c->log->debug( sprintf( "Action details: \nclass: %s\nnamespace: %s\nreverse: %s\nprivate_path: %s", $action->class, $action->namespace, $action->reverse, $action->private_path ) ) if $c->debug;
#  	$c->log->debug( "Value of menu_parents is: " . p($menu_parents) ) if $c->debug;

# 	my $c_nav_config   = $c->config->{navigation}          || {};
# 	my $ctr_nav_config = $controller->config->{navigation} || {};

	my $action_key = $action->namespace . '/' . $action->name;
# 	$c->log->debug( sprintf( "Adding action item for path: %s with parent: %s in controller: %s", $action_key, $action->attributes->{MenuParent}->[0] || '', ref $controller ) ) if $c->debug;

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

		my $conditions = $c_nav_item->{conditions}  // $ctr_nav_item->{conditions}  // $act_attrs->{MenuCond} // [];
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

		my $action_url_args   = $act_attrs->{MenuArgs} // [];
		my $action_url_params = $c_nav_item->{query_params}  // $ctr_nav_item->{query_params}  // $act_attrs->{MenuQueryParams}->[$i] // $last_item->{query_params}  // '',
		my $url;
		my $url_cb;
		if ( scalar @$action_url_args >= 1 || $action_url_params  ) {
			$url_cb = $self->_build_url_coderef( $action, $action_url_args, $action_url_params );
		} else {
			$url = $c->uri_for_action($action);
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
			path        => $action_key, (
				$url_cb
				? ( url_cb => $url_cb )
				: ( url => $url )
			),
			query_params => $action_url_params,
			order        => $c_nav_item->{order} // $ctr_nav_item->{order} // $act_attrs->{MenuOrder}->[$i] // $last_item->{order} // 0,
			label        => $c_nav_item->{label} // $ctr_nav_item->{label} // $act_attrs->{Menu}->[$i] // $last_item->{label} // '',
			title        => $c_nav_item->{title} // $ctr_nav_item->{title} // $act_attrs->{MenuTitle}->[$i] // $last_item->{title} // '',
			icon         => $c_nav_item->{icon} // $ctr_nav_item->{icon} // $act_attrs->{MenuIcon}->[$i] // $last_item->{icon} // '',
			dom_id       => $c_nav_item->{dom_id} // $ctr_nav_item->{dom_id} // $act_attrs->{MenuDomId}->[$i] // $last_item->{dom_id} // '',
			css_classes => $c_nav_item->{css_classes} // $ctr_nav_item->{css_classes} // $act_attrs->{MenuCssClasses} // [],
			category => $c_nav_item->{category} // $ctr_nav_item->{category} // $act_attrs->{MenuCategory}->[$i] // $last_item->{category} // $self->default_category,
			description    => $c_nav_item->{description}    // $ctr_nav_item->{description}    // $act_attrs->{MenuDescription}->[$i] // $last_item->{description}    // '',
			required_roles => $c_nav_item->{required_roles} // $ctr_nav_item->{required_roles} // $act_attrs->{MenuRoles}->[$i]       // $last_item->{required_roles} // '',
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
# 			$c->log->debug( "Checking menu exists: " . $menu_path ) if $c->debug;

			my $mp = $menubar . $menu_path;
			if ( $mp && !$self->get_menu($mp) ) {
# 				$c->log->debug( "Setting menu - menu_path is: " . $menu_path ) if $c->debug;
				my $c_nav_item_menu   = $c->get_navigation_item($mp)          || {};
				my $ctr_nav_item_menu = $controller->get_navigation_item($mp) || {};
				$c->log->debug(
					sprintf(
						"Setting menu %s with label - ctx: %s, ctrl: %s, attr: %s, path: %s",
						$mp,
						$c_nav_item_menu->{label} || '', $ctr_nav_item_menu->{label} || '',
						$act_attrs->{MenuParentLabel}->[0] || '', $menu_path_item
					)
				) if $c->debug;
				$self->set_menus(
					$mp, {
						path        => $c_nav_item_menu->{path}        // $ctr_nav_item_menu->{path}        // $act_attrs->{MenuParentPath}->[0]        // $menu_path,
						order       => $c_nav_item_menu->{order}       // $ctr_nav_item_menu->{order}       // $act_attrs->{MenuParentOrder}->[0]       // 0,
						label       => $c_nav_item_menu->{label}       // $ctr_nav_item_menu->{label}       // $act_attrs->{MenuParentLabel}->[0]       // $menu_path_item,
						title       => $c_nav_item_menu->{title}       // $ctr_nav_item_menu->{title}       // $act_attrs->{MenuParentTitle}->[0]       // '',
						icon        => $c_nav_item_menu->{icon}        // $ctr_nav_item_menu->{icon}        // $act_attrs->{MenuParentIcon}->[0]        // '',
						category    => $c_nav_item_menu->{category}    // $ctr_nav_item_menu->{category}    // $act_attrs->{MenuParentCategory}->[0]    // $self->default_category,
						description => $c_nav_item_menu->{description} // $ctr_nav_item_menu->{description} // $act_attrs->{MenuParentDescription}->[0] // '',
						dom_id      => $c_nav_item_menu->{dom_id}      // $ctr_nav_item_menu->{dom_id}      // $act_attrs->{MenuParentDomId}->[0]       // '',
						css_classes => $c_nav_item_menu->{css_classes} // $ctr_nav_item_menu->{css_classes} // $act_attrs->{MenuParentCssClasses}       // [],
					}
				);
			} ## end if ( $menu_path && !$self->get_menu...)
			pop @sub_menus;

		} ## end while ( scalar @sub_menus >= 1 )


	} ## end for ( my $i = 0; $i <= $#$menu_parents...)
} ## end sub add_action_menu_item


sub _build_url_coderef {
	my ( $self, $action, $action_args, $query_params ) = @_;
	my $sub = sub {
		my $ctx = shift;
		@$action_args = map {
			my @elems = split( '\.', $_ );
			my $elem1 = shift @elems;
			my $val;
			if ( $ctx->can($elem1) ) {
				$val = $ctx->$elem1;
			} elsif ( exists $ctx->stash->{$elem1} ) {
				$val = $ctx->stash->{$elem1};
			} else {
				$val = $elem1;
			}
			foreach my $elem (@elems) {
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
			$val;
		} @$action_args;
		if (ref $query_params eq 'HASH') {
			# do nothing??
		} elsif (! ref $query_params) {
			my $parsed_params = {};
			my $callback = sub {
				my ($name, $value) = @_;
				my @elems = split( '\.', $value );
				my $elem1 = shift @elems;
				my $val;
				if ( $ctx->can($elem1) ) {
					$val = $ctx->$elem1;
				} elsif ( exists $ctx->stash->{$elem1} ) {
					$val = $ctx->stash->{$elem1};
				} else {
					$val = $elem1;
				}
				foreach my $elem (@elems) {
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
				$parsed_params->{$name} = $val;
			};
 
			url_params_each($query_params, $callback);
			$query_params = $parsed_params;
		} else {
			warn "query_params is something unexpected";
		}
		
		$ctx->uri_for_action( $action, $action_args, $query_params );
	};
	return $sub;
} ## end sub _build_url_coderef

__PACKAGE__->meta->make_immutable;


1;

