class CreateSoundSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :sound_settings do |t|
      t.jsonb :volumes, default: {}, null: false

      t.timestamps
    end
  end
end
