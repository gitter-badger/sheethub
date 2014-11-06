class DimensionsValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    if record.send("#{attribute}?".to_sym)
      image = value.queued_for_write[:original]
      dimensions = Paperclip::Geometry.from_file(image.path)
      width = options[:width]
      height = options[:height]

      record.errors[attribute] << "Width must be #{width}px" unless dimensions.width <= width
      record.errors[attribute] << "Height must be #{height}px" unless dimensions.height <= height
    end
  end
end