# frozen_string_literal: true

class AppsController < ApplicationController
  include AppArchived

  before_action :authenticate_user! unless Setting.guest_mode
  before_action :set_app, only: %i[show edit update destroy new_owner update_owner download_analytics]
  before_action :set_selected_schemes_and_channels, only: %i[edit]
  before_action :process_scheme_and_channel, only: %i[create]
  before_action :set_owner, only: %i[ new_owner update_owner ]

  before_action -> { set_app_breadcrumbs(app: @app) }, only: %i[show edit update destroy new_owner update_owner download_analytics]

  def index
    @title = t('.title')
    base_scope = manage_user_or_guest_mode? ? App.active : current_user.apps.active 
    base_scope = params[:search].present? ? base_scope.search_by_name(params[:search]) : base_scope
    @apps = params[:sort].present? ? base_scope.sort_by_name(params[:sort]) : base_scope
    authorize @apps if @apps.present?
  end

  def show
    @title = @app.name
  end

  def download_analytics
    @period = download_analytics_period
    @title = t('.title', app: @app.name)
    @buckets = download_analytics_buckets(@period)
    @series = download_analytics_series(@app, @buckets, @period)
    @max_downloads = @series.flat_map { |item| item[:values].map { |value| value[:count] } }.max.to_i
  end

  def new
    @title = t('.title')
    @app = App.new
    authorize @app

    @app.schemes.build
  end

  def edit
    raise_if_app_archived!(@app)

    @title = t('.title')
  end

  def create
    @app = App.new(app_params)
    authorize @app
    return render :new, status: :unprocessable_entity unless @app.save

    create_owner
    create_schemes_and_channels

    flash.now[:notice] = t('activerecord.success.create', key: "#{@app.name} #{t('apps.title')}")
    respond_to do |format|
      format.html { redirect_to apps_path }
      format.turbo_stream
    end
  end

  def update
    raise_if_app_archived!(@app)

    @app.update(app_params)
    respond_to do |format|
      format.html { redirect_to apps_path }
      format.turbo_stream
    end
  end

  def destroy
    @app.destroy
    destroy_app_data

    respond_to do |format|
      format.any { redirect_to apps_path }
    end
  end

  def new_owner
    raise_if_app_archived!(@app)

    @title = t('.title')
  end

  def update_owner
    raise_if_app_archived!(@app)

    @title = t('apps.new_owner.title')
    @previous_user = @collaborator.user
    user_id = owner_params[:user_id]
    if @previous_user.id == user_id.to_i
      notice = t('activerecord.errors.messages.same_value', key: t('apps.new_owner.title'))
      return redirect_to @collaborator.app, notice: notice, status: :see_other
    end

    new_owner = User.find(user_id)
    if existed_collaborator = @app.collaborators.find_by(user: new_owner)
      existed_collaborator.destroy
    end

    return render :new_owner, status: :unprocessable_entity unless @collaborator.update(user: new_owner)

    notice = t('activerecord.success.update', key: t('apps.new_owner.title'))
    flash.now[:notice] = notice
    respond_to do |format|
      format.html { redirect_to @app }
      format.turbo_stream
    end
  end

  private

  def destroy_app_data
    require 'fileutils'

    app_binary_path = Rails.root.join('public', 'uploads', 'apps', "a#{@app.id}")
    FileUtils.rm_rf(app_binary_path) if Dir.exist?(app_binary_path)
  end

  def set_owner
    @collaborator = @app.collaborators.find_by(owner: true)
  end

  def create_owner
    @app.create_owner(current_user)
  end

  def create_schemes_and_channels
    @schemes.each do |scheme_name|
      scheme = @app.schemes.create(name: scheme_name)
      next if @channels.empty?

      @channels.each do |channel_name|
        scheme.channels.create name: channel_name, device_type: channel_name.downcase.to_sym
      end
    end
  end

  # def update_schemes_and_channels
  #   existed_schemes = @app.schemes.all

  #   @schemes.each do |scheme_name|
  #     scheme = @app.schemes.find_by(name: scheme_name)


  #     @channels.each do |channel_name|
  #       scheme.channels.create name: channel_name, device_type: channel_name.downcase.to_sym
  #     end
  #   end
  # end

  def set_selected_schemes_and_channels
    @schemes = []
    @channels = []
    @app.schemes.each do |scheme|
      @schemes << scheme.name

      channels = scheme.channels.pluck(:name)
      channels.each do |channel_name|
        @channels << channel_name unless @channels.include?(channel_name)
      end
    end
  end

  def process_scheme_and_channel
    @schemes = app_params.delete(:scheme_attributes)[:name].reject(&:empty?)
    @channels = app_params.delete(:channel_attributes)[:name].reject(&:empty?)
  end

  def set_app
    @app = App.find(params[:id])
    authorize @app
  end

  def download_analytics_period
    period = params[:period].to_s
    %w[day month year].include?(period) ? period : 'day'
  end

  def download_analytics_buckets(period)
    today = Time.zone.today

    case period
    when 'month'
      first_month = today.beginning_of_month << 11
      12.times.map { |index| first_month >> index }
    when 'year'
      first_year = Date.new(today.year - 4, 1, 1)
      5.times.map { |index| first_year >> (index * 12) }
    else
      first_day = today - 13.days
      14.times.map { |index| first_day + index.days }
    end
  end

  def download_analytics_series(app, buckets, period)
    counts = download_counts_by_device_type_and_bucket(app, buckets, period)

    app_download_device_types(app).map do |device_type|
      values = buckets.map do |bucket|
        key = download_bucket_key(bucket, period)
        { label: download_bucket_label(bucket, period), count: counts.fetch([device_type, key], 0) }
      end

      { device_type: device_type, total: values.sum { |value| value[:count] }, values: values }
    end
  end

  def app_download_device_types(app)
    Channel
      .unscoped
      .joins(:scheme)
      .where(schemes: { app_id: app.id })
      .distinct
      .pluck(Arel.sql('channels.device_type'))
      .sort
  end

  def download_counts_by_device_type_and_bucket(app, buckets, period)
    unit = { 'day' => 'day', 'month' => 'month', 'year' => 'year' }.fetch(period)
    bucket_sql = Arel.sql("DATE_TRUNC('#{unit}', release_downloads.created_at)")

    ReleaseDownload
      .joins(release: { channel: :scheme })
      .where(schemes: { app_id: app.id }, created_at: download_bucket_range(buckets, period))
      .group('channels.device_type', bucket_sql)
      .count
      .each_with_object({}) do |((device_type, bucket_time), count), result|
        result[[device_type, download_bucket_key(bucket_time.in_time_zone.to_date, period)]] = count
      end
  end

  def download_bucket_range(buckets, period)
    first_bucket = buckets.first
    last_bucket = buckets.last

    case period
    when 'month'
      first_bucket.beginning_of_month.beginning_of_day..last_bucket.end_of_month.end_of_day
    when 'year'
      first_bucket.beginning_of_year.beginning_of_day..last_bucket.end_of_year.end_of_day
    else
      first_bucket.beginning_of_day..last_bucket.end_of_day
    end
  end

  def download_bucket_key(bucket, period)
    case period
    when 'month'
      bucket.strftime('%Y-%m')
    when 'year'
      bucket.strftime('%Y')
    else
      bucket.strftime('%Y-%m-%d')
    end
  end

  def download_bucket_label(bucket, period)
    case period
    when 'month'
      bucket.strftime('%Y-%m')
    when 'year'
      bucket.strftime('%Y')
    else
      bucket.strftime('%m/%d')
    end
  end

  def app_params
    @app_params ||= params.require(:app)
                          .permit(
                            :name,
                            scheme_attributes: { name: [] },
                            channel_attributes: { name: [] },
                          )
  end

  def render_not_found_entity_response(e)
    redirect_to apps_path, notice: t('apps.messages.failture.not_found_app', id: e.id)
  end

  def owner_params
    params.require(:collaborator).permit(:user_id)
  end
end
