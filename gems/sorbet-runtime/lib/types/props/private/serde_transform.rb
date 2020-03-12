# frozen_string_literal: true
# typed: strict

module T::Props
  module Private
    module SerdeTransform
      extend T::Sig

      class Serialize; end
      private_constant :Serialize
      class Deserialize; end
      private_constant :Deserialize
      ModeType = T.type_alias {T.any(Serialize, Deserialize)}
      private_constant :ModeType

      module Mode
        SERIALIZE = T.let(Serialize.new.freeze, Serialize)
        DESERIALIZE = T.let(Deserialize.new.freeze, Deserialize)
      end

      sig do
        params(
          type: T.any(T::Types::Base, Module),
          mode: ModeType,
          varname: String,
        )
        .returns(T.nilable(String))
        .checked(:never)
      end
      def self.generate(type, mode, varname)
        case type
        when T::Types::TypedArray
          inner = generate(type.type, mode, 'v')
          if inner.nil?
            "#{varname}.dup"
          else
            "#{varname}.map {|v| #{inner}}"
          end
        when T::Types::TypedSet
          inner = generate(type.type, mode, 'v')
          if inner.nil?
            "#{varname}.dup"
          else
            "Set.new(#{varname}) {|v| #{inner}}"
          end
        when T::Types::TypedHash
          keys = generate(type.keys, mode, 'k')
          values = generate(type.values, mode, 'v')
          if keys && values
            "#{varname}.each_with_object({}) {|(k,v),h| h[#{keys}] = #{values}}"
          elsif keys
            "#{varname}.transform_keys {|k| #{keys}}"
          elsif values
            "#{varname}.transform_values {|v| #{values}}"
          else
            "#{varname}.dup"
          end
        when T::Types::Simple
          raw = type.raw_type
          if raw < T::Props::Serializable
            handle_serializable_subtype(varname, raw, mode)
          elsif raw.singleton_class < T::Props::CustomType
            handle_custom_type(varname, T.unsafe(raw), mode)
          elsif T::Props::Utils.class_of_scalar_type?(raw)
            nil
          else
            "T::Props::Utils.deep_clone_object(#{varname})"
          end
        when T::Types::Union
          non_nil_type = T::Utils.unwrap_nilable(type)
          if non_nil_type
            inner = generate(non_nil_type, mode, varname)
            if inner.nil?
              nil
            else
              "#{varname}.nil? ? nil : #{inner}"
            end
          else
            "T::Props::Utils.deep_clone_object(#{varname})"
          end
        when T::Types::Enum
          generate(T::Utils.lift_enum(type), mode, varname)
        else
          if type.singleton_class < T::Props::CustomType
            # Sometimes this comes wrapped in a T::Types::Simple and sometimes not
            handle_custom_type(varname, T.unsafe(type), mode)
          else
            "T::Props::Utils.deep_clone_object(#{varname})"
          end
        end
      end

      sig {params(varname: String, type: Module, mode: ModeType).returns(String).checked(:never)}
      private_class_method def self.handle_serializable_subtype(varname, type, mode)
        case mode
        when Serialize
          "#{varname}.serialize(strict)"
        when Deserialize
          type_name = T.must(module_name(type))
          "#{type_name}.from_hash(#{varname})"
        else
          T.absurd(mode)
        end
      end

      sig {params(varname: String, type: Module, mode: ModeType).returns(String).checked(:never)}
      private_class_method def self.handle_custom_type(varname, type, mode)
        case mode
        when Serialize
          type_name = T.must(module_name(type))
          "T::Props::CustomType.checked_serialize(#{type_name}, #{varname})"
        when Deserialize
          type_name = T.must(module_name(type))
          "#{type_name}.deserialize(#{varname})"
        else
          T.absurd(mode)
        end
      end

      # Guard against overrides of `name` or `to_s`
      MODULE_NAME = T.let(Module.instance_method(:name), UnboundMethod)
      private_constant :MODULE_NAME

      sig {params(type: Module).returns(T.nilable(String)).checked(:never)}
      private_class_method def self.module_name(type)
        MODULE_NAME.bind(type).call
      end
    end
  end
end
