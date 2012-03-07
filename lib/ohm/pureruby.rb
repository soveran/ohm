require "ohm/transaction"

module Ohm
  class Model
    module PureRuby
      def _initialize_id
        @id = model.new_id.to_s
      end

      def save(&block)
        return if not valid?
        save!(&block)
      end

      def save!
        transaction do |t|
          t.watch(*_unique_keys)
          t.watch(key) if not new?

          t.before do
            _initialize_id if new?
          end

          t.read do |store|
            _verify_uniques
            store.existing = key.hgetall
          end

          t.write do |store|
            model.key[:all].sadd(id)
            _delete_uniques(store.existing)
            _delete_indices(store.existing)
            _save
            _save_indices
            _save_uniques
          end

          yield t if block_given?
        end

        return self
      end

      def _unique_keys
        model.uniques.map { |att| model.key[:uniques][att] }
      end

      def _save
        key.del
        key.hmset(*_skip_empty(attributes).flatten)
      end

      def _verify_uniques
        if att = _detect_duplicate
          raise UniqueIndexViolation, "#{att} is not unique."
        end
      end

      def _detect_duplicate
        model.uniques.detect do |att|
          id = model.key[:uniques][att].hget(attributes[att])
          id && id != self.id.to_s
        end
      end

      def _save_uniques
        model.uniques.each do |att|
          model.key[:uniques][att].hset(attributes[att], id)
        end
      end

      def _delete_uniques(atts)
        model.uniques.each do |att|
          model.key[:uniques][att].hdel(atts[att.to_s])
        end
      end

      def _delete_indices(atts)
        model.indices.each do |att|
          val = atts[att.to_s]

          if val
            model.key[:indices][att][val].srem(id)
          end
        end
      end

      def _save_indices
        model.indices.each do |att|
          model.key[:indices][att][attributes[att]].sadd(id)
        end
      end

      def delete
        transaction do |t|
          t.read do |store|
            store.existing = key.hgetall
          end

          t.write do |store|
            _delete_uniques(store.existing)
            _delete_indices(store.existing)
            model.collections.each { |e| key[e].del }
            model.key[:all].srem(id)
            key.del
          end

          yield t if block_given?
        end
      end

      def transaction
        model.uniques; model.indices; model.collections # memoized

        txn = Transaction.new { |t| yield t }
        txn.commit(db)
      end
    end

    include PureRuby
  end
end
