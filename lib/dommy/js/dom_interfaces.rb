# frozen_string_literal: true

module Dommy
  module Js
    # Derives WebIDL interface metadata for a Dommy DOM object: the most-derived
    # interface name and the single-inheritance chain up to the root
    # (EventTarget for nodes). This mirrors the JS prototype chain the bridge
    # builds so `instanceof` / Object.prototype.toString resolve correctly.
    #
    # Engine-agnostic, and the single home for DOM interface hierarchy knowledge:
    # BASE_CHAINS (seeded eagerly on the JS side) must stay consistent with what
    # #chain_for derives from real objects.
    module DomInterfaces
      # Dommy class basename -> WebIDL interface name, where they diverge.
      # Anything not listed uses the class basename verbatim (HTMLDivElement, …).
      NAME_OVERRIDES = {
        "TextNode" => "Text",
        "CommentNode" => "Comment",
        "CharacterDataNode" => "CharacterData",
        "Fragment" => "DocumentFragment",
        "ClassList" => "DOMTokenList",
        "DatasetMap" => "DOMStringMap",
        "StyleDeclaration" => "CSSStyleDeclaration"
      }.freeze

      # Base interface chains seeded eagerly on the JS side so `instanceof Node`
      # / `typeof HTMLElement` resolve before an instance of that exact type has
      # crossed. Concrete leaves (HTMLButtonElement, …) are built lazily from
      # #chain_for when an instance crosses. Keep consistent with #chain_for.
      BASE_CHAINS = [
        %w[Node EventTarget],
        %w[Element Node EventTarget],
        %w[HTMLElement Element Node EventTarget],
        %w[SVGElement Element Node EventTarget],
        %w[CharacterData Node EventTarget],
        %w[Text CharacterData Node EventTarget],
        %w[Comment CharacterData Node EventTarget],
        %w[Document Node EventTarget],
        %w[DocumentFragment Node EventTarget],
        %w[DocumentType Node EventTarget],
        %w[Attr Node EventTarget],
        %w[Event],
        %w[CustomEvent Event],
        %w[MouseEvent Event],
        %w[KeyboardEvent Event],
        %w[DOMException]
      ].freeze

      module_function

      # { "name" => most-derived interface, "chain" => [...] } for a host object.
      def info(obj)
        chain = chain_for(obj)
        {"name" => chain.first, "chain" => chain}
      end

      # Walk the Dommy class superclass chain (HTMLDivElement < HTMLElement <
      # Element), then append the module-provided base interfaces (Node ->
      # EventTarget) for nodes, since Dommy models Node as a mixin rather than a
      # superclass. Stops at the first foreign superclass (Object, or
      # StandardError for DOMException) so non-DOM ancestors stay out.
      def chain_for(obj)
        names = []
        klass = obj.class
        while klass && klass.name&.start_with?("Dommy::")
          name = name_for(klass)
          names << name if name && !names.include?(name)
          klass = klass.superclass
        end
        if defined?(Dommy::Node) && obj.is_a?(Dommy::Node)
          names << "Node" unless names.include?("Node")
          names << "EventTarget" unless names.include?("EventTarget")
        end
        names
      end

      def name_for(klass)
        base = klass.name&.split("::")&.last
        return nil unless base

        NAME_OVERRIDES.fetch(base, base)
      end
    end
  end
end
