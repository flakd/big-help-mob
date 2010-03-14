module AdminHelper
  
  def collection_sidebar
    sidebar_menu(parent_sidebar_content + resources_sidebar_content)
  end
  
  def object_sidebar
    name = current_resource_name
    inner_menu = parent_sidebar_content + resources_sidebar_content(name) + resource_sidebar_content(name)
    sidebar_menu(inner_menu)
  end
  
  def menu_link(text, *args, &blk)
    content_tag(:li, link_to(text, *args, &blk), :class => 'menu-item')
  end
  alias ml menu_link
  
  def sidebar_menu(content = nil, &blk)
    content = content.to_s
    content << capture(&blk) if blk.present?
    content = content_tag(:ul, content, :class => 'sidebar-menu')
    blk.present? ? concat(content) : content
  end
  
  def sidebar_klass_name(klass)
    klass_name = klass.name.singularize.underscore.humanize
    controller_i18n_path = controller.controller_path.split("/").join(".")
    I18n.t(controller_i18n_path.to_sym, :scope => :sidebar, :default => klass_name.humanize)
  end
  
  def current_resource_name
    sidebar_klass_name(resource_class).titleize
  end
  
  def current_parent_name
    sidebar_klass_name(parent_class).titleize
  end
  
  def individual_resource_links(r)
    content_tag(:ul, [
      ml("View", resource_url(r)),
      ml("Edit", edit_resource_url(r)),
      ml("Remove", resource_url(r), :method => :delete,
      :confirm => I18n.t(:'sidebar.confirmation.remove', :object_name => name))
    ].join)
  end
  
  def default_collection_columns
    klass = resource_class
    if klass.const_defined?(:INDEX_COLUMNS)
      klass::INDEX_COLUMNS
    else
      klass.column_names - [:created_at, :updated_at]
    end
  end
  
  # Generalized Sidebar Content
  
  def parent_sidebar_content
    returning "" do |content|
      if respond_to?(:parent?) && parent?
        parent_name = current_parent_name
        content << ml("View #{parent_name}", parent_url)
        content << ml("Edit #{parent_name}", File.join(parent_url, 'edit'))
      end
    end
  end
  
  def resources_sidebar_content(name = current_resource_name)
    returning "" do |content|
      content << ml("All #{name.pluralize}", collection_url)
      content << ml("Add #{name}", new_resource_url)
    end
  end
  
  def resource_sidebar_content(name = current_resource_name)
    returning "" do |content|
      content << ml("View #{name}", resource_url)
      content << ml("Edit #{name}", edit_resource_url)
      content << ml("Remove #{name}", resource_url, :method => :delete,
        :confirm => I18n.t(:'sidebar.confirmation.remove', :object_name => name))
    end
  end
  
  
end