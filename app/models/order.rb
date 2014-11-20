# Encapsulates Orders, an association class between Sheets and Buyers.
class Order < ActiveRecord::Base
  EXPIRATION_TIME = 600
  ORDER_UNIQUENESS_VALIDATION_MESSAGE = "Users cannot have multiple orders of the same Sheet."
  WATERMARK_PATH = "#{Rails.root}/public/images/watermark.png"

  validates :sheet_id, uniqueness: { scope: :user_id,
                       message: ORDER_UNIQUENESS_VALIDATION_MESSAGE }

  has_attached_file :pdf,
                    :hash_secret => Sheet::SHEET_HASH_SECRET, #TODO: Use ENV for this
                    :default_url => Sheet::PDF_DEFAULT_URL, #TODO: point to special Missing file route
                    :preserve_files => "true"
  validates_attachment_content_type :pdf, :content_type => [ 'application/pdf' ]

  belongs_to :user
  belongs_to :sheet

  enum status: %w(processing completed failed)

  def complete
    unless completed?
      update(status: Order.statuses[:completed], purchased_at: Time.now)
      sheet.increment!(:total_sold)
      OrderMailer.purchase_receipt_email(self).deliver
      OrderMailer.sheet_purchased_email(self).deliver
    end
  end

  def generate_watermarked_pdf
    pdf_path = sheet.pdf_download_url
    watermarked = MiniMagick::Image.open(pdf_path)
    watermark = MiniMagick::Image.open(File.expand_path(WATERMARK_PATH))
    composited = watermarked.pages.inject([]) do |composited, page|
      composited << page.composite(watermark) do |c|
        c.compose "Over"
        c.gravity "SouthEast"
      end
    end
    MiniMagick::Tool::Convert.new do |b|
      composited.each { |page| b << page.path }
      b << watermarked.path
    end
    self.pdf = File.open(watermarked.path)
    self.save!
  end

  def has_latest_pdf?
    return false unless pdf.updated_at
    sheet.pdf.updated_at < pdf.updated_at
  end

  def pdf_download_url
    return false unless completed? # If this evaluates true, user has not completed purchase
    generate_watermarked_pdf unless has_latest_pdf?
    pdf.expiring_url(EXPIRATION_TIME)
  end

  def amount
    amount_cents.to_f / 100
  end

  def royalty
    (Sheet::USER_ROYALTY_PERCENTAGE * amount - paypal_transaction_fees).round(2)
  end

  def paypal_transaction_fees
    (0.029 * amount) + 0.3
  end

  def self.get_adaptive_payment_details(payKey)
    api = PayPal::SDK::AdaptivePayments::API.new
    payment_details_request = api.build_payment_details
    payment_details_request.payKey = payKey
    payment_details_response = api.payment_details(payment_details_request)
    if payment_details_response.success?
      return payment_details_response
    else
      fail "Payment Details for payKey #{payKey} Not Found"
    end
  end

end
