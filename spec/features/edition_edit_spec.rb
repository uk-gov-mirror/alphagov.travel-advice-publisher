require 'spec_helper'
require 'gds_api/test_helpers/panopticon'

feature "Edit Edition page", :js => true do
  before :each do
    login_as_stub_user
  end

  context "creating new editions" do
    scenario "when no editions are present, create a new edition" do
      visit "/admin/countries/aruba"

      click_on "Create new edition"

      page.should have_field("Search title", :with => "Aruba travel advice")

      within(:css, ".tabbable .nav") do
        page.should have_link("Edit")
        page.should have_link("History & Notes")
      end

      within(:css, ".tabbable .nav") do
        click_on "History & Notes"
      end

      within(:css, "#history") do
        page.should have_content("New version by Joe Bloggs")
      end
    end

    scenario "create an edition from an archived edition" do
      @edition = FactoryGirl.create(:archived_travel_advice_edition, :country_slug => "albania", :title => "An archived title")

      visit "/admin/editions/#{@edition._id}/edit"

      within(:css, ".workflow_buttons") do
        click_on "Create new edition"
      end

      page.should have_field("Search title", :with => @edition.title)
      current_path.should_not == "/admin/editions/#{@edition._id}/edit"
    end

    scenario "create an edition from a published edition" do
      @edition = FactoryGirl.create(:published_travel_advice_edition, :country_slug => "albania", :title => "A published title")
      @edition.actions.build(:request_type => Action::NEW_VERSION)
      @edition.actions.build(:request_type => Action::PUBLISH, :requester => User.first, :comment => "Made some changes...")
      @edition.save(:validate => false)

      visit "/admin/editions/#{@edition._id}/edit"

      within(:css, ".workflow_buttons") do
        click_on "Create new edition"
      end

      page.should have_field("Search title", :with => @edition.title)
      current_path.should_not == "/admin/editions/#{@edition._id}/edit"

      within "#history" do
        page.should have_content("Notes for version 2")
        page.should have_content("New version by Joe Bloggs")

        page.should have_content("Notes for version 1")
        page.should have_content("Publish by Joe Bloggs")
        page.should have_content("Made some changes...")
        page.should have_content("New version by GOV.UK Bot")
      end
    end

    scenario "should not allow creation of drafts if draft already exists" do
      @edition = FactoryGirl.create(:published_travel_advice_edition, :country_slug => "albania", :title => "A published title")
      @draft = FactoryGirl.create(:travel_advice_edition, :country_slug => 'albania', :state => "draft")

      visit "/admin/editions/#{@edition._id}/edit"

      within(:css, ".workflow_buttons") do
        page.should_not have_link("Create new edition")
      end
    end
  end

  scenario "inspecting the edit form, and adding content" do
    @edition = FactoryGirl.create(:draft_travel_advice_edition, :country_slug => 'albania')
    visit "/admin/editions/#{@edition._id}/edit"

    within('h1') { page.should have_content "Editing Albania Version 1" }

    within '#edit' do
      within_section "the fieldset labelled Metadata" do
        page.should have_field("Search title", :with => @edition.title)
        page.should have_field("Search description")

        # The first version can't be a minor update...
        page.should_not have_field("Minor update")
        page.should have_field("Change description")
      end

      within_section "the fieldset labelled Summary content" do
        page.should have_unchecked_field("The FCO advise against all travel to the whole country")
        page.should have_unchecked_field("The FCO advise against all travel to parts of the country")
        page.should have_unchecked_field("The FCO advise against all but essential travel to the whole country")
        page.should have_unchecked_field("The FCO advise against all but essential travel to parts of the country")

        page.should have_field("Summary")
      end

      within_section "the fieldset labelled Parts" do
        # Should be no parts by default
        page.should_not have_selector('#parts .part')

        page.should have_button "Add new part"
      end
    end

    fill_in 'Search title', :with => 'Travel advice for Albania'
    fill_in 'Search description', :with => "Read this if you're planning on visiting Albania"

    fill_in 'Change description', :with => "Made changes to all the stuff"

    fill_in 'Summary', :with => "Summary of the situation in Albania"

    click_on 'Add new part'
    within :css, '#parts div.part:first-of-type' do
      fill_in 'Title', :with => 'Part One'
      fill_in 'Body',  :with => 'Body text'
      fill_in 'Slug',  :with => 'part-one'
    end

    click_on 'Add new part'
    within :css, '#parts div.part:nth-of-type(2)' do
      fill_in 'Title', :with => 'Part Two'
      fill_in 'Body',  :with => 'Body text'
      fill_in 'Slug',  :with => 'part-two'
    end

    within(:css, '.workflow_buttons') { click_on 'Save' }

    all(:css, '#parts > div.part').length.should == 2

    current_path.should == "/admin/editions/#{@edition._id}/edit"

    @edition.reload
    @edition.title.should == "Travel advice for Albania"
    @edition.overview.should == "Read this if you're planning on visiting Albania"
    @edition.summary.should == "Summary of the situation in Albania"
    @edition.change_description.should == "Made changes to all the stuff"

    @edition.parts.size.should == 2
    one = @edition.parts.first
    one.title.should == 'Part One'
    one.slug.should == 'part-one'
    one.body.should == 'Body text'
    one.order.should == 1
    two = @edition.parts.last
    two.title.should == 'Part Two'
    two.slug.should == 'part-two'
    two.body.should == 'Body text'
    two.order.should == 2
  end

  scenario "Seeing the minor update toggle on the edit form for non-first versions" do
    FactoryGirl.create(:published_travel_advice_edition, :country_slug => 'albania')
    @edition = FactoryGirl.create(:draft_travel_advice_edition, :country_slug => 'albania', :minor_update => true)
    visit "/admin/editions/#{@edition._id}/edit"

    within('h1') { page.should have_content "Editing Albania Version 2" }

    within '#edit' do
      within_section "the fieldset labelled Metadata" do
        page.should have_checked_field("Minor update")
        page.find_field("Change description").should_not be_visible

        uncheck "Minor update"
        page.find_field("Change description").should be_visible
      end
    end

    click_on "Save"

    @edition.reload
    @edition.minor_update.should == false
  end

  scenario "slug for parts should be automatically generated" do
    @edition = FactoryGirl.create(:travel_advice_edition, :country_slug => 'albania', :state => 'draft')
    visit "/admin/editions/#{@edition._id}/edit"

    click_on 'Add new part'
    within :css, '#parts div.part:first-of-type' do
      fill_in 'Title', :with => 'Part One'
      fill_in 'Body',  :with => 'Body text'

      find(:css, ".slug").value.should == 'part-one'
    end
  end

  scenario "removing a part from an edition" do
    @edition = FactoryGirl.build(:travel_advice_edition, :country_slug => 'albania', :state => 'draft')
    @edition.parts.build(:title => 'Part One', :body => 'Body text', :slug => 'part-one')
    @edition.parts.build(:title => 'Part Two', :body => 'Body text', :slug => 'part-two')
    @edition.save!

    @edition.parts.build
    p1 = @edition.parts.first.update_attributes(
      :title => 'Part One', :body => 'Body text', :slug => 'part-one')

    @edition.parts.build
    p2 = @edition.parts.second.update_attributes(
      :title => 'Part Two', :body => 'Body text', :slug => 'part-two')

    visit "/admin/editions/#{@edition._id}/edit"

    click_on 'Part Two'

    within :css, '#parts div.part:nth-of-type(2)' do
      click_on 'Remove part'
    end

    page.should have_css('#part-two', :visible => false)

    # page.execute_script("$('.remove-associated').last().prev(':input').val('1')")

    within(:css, '.workflow_buttons') { click_on 'Save' }

    current_path.should == "/admin/editions/#{@edition._id}/edit"

    pending "This is not setting the _destroy field on the part to '1' despite the input value changing in the browser."

    page.should_not have_content("Part Two")
  end

  scenario "adding an invalid part" do
    @edition = FactoryGirl.create(:travel_advice_edition, :country_slug => 'albania', :state => 'draft')
    visit "/admin/editions/#{@edition._id}/edit"

    click_on "Add new part"
    within :css, '#parts div.part:first-of-type' do
      fill_in 'Body',  :with => 'Body text'
      fill_in 'Slug',  :with => 'part-one'
    end

    click_on "Save"

    page.should have_content("We had some problems saving: Parts is invalid.")
  end

  scenario "save and publish an edition" do
    @old_edition = FactoryGirl.create(:published_travel_advice_edition, :country_slug => 'albania')
    @edition = FactoryGirl.create(:draft_travel_advice_edition, :country_slug => 'albania', :title => 'Albania travel advice',
                                  :alert_status => TravelAdviceEdition::ALERT_STATUSES[1..0],
                                  :change_description => "Stuff changed", :minor_update => false,
                                  :overview => "The overview", :summary => "## Summary")

    WebMock.stub_request(:put, %r{\A#{GdsApi::TestHelpers::Panopticon::PANOPTICON_ENDPOINT}/artefacts}).
      to_return(:status => 200, :body => "{}")

    now = Time.now.utc
    Timecop.freeze(now) do
      visit "/admin/editions/#{@edition.to_param}/edit"

      click_on "Add new part"
      within :css, "#parts div.part:first-of-type" do
        fill_in "Title", :with => "Part One"
        fill_in "Body",  :with => "Body text"
      end

      click_on "Save & Publish"
    end

    @old_edition.reload
    @old_edition.should be_archived

    @edition.reload
    @edition.parts.size.should == 1
    @edition.parts.first.title.should == "Part One"
    @edition.should be_published

    @edition.published_at.to_i.should == now.to_i
    action = @edition.actions.last
    action.request_type.should == Action::PUBLISH
    action.comment.should == "Stuff changed"

    WebMock.should have_requested(:put, "#{GdsApi::TestHelpers::Panopticon::PANOPTICON_ENDPOINT}/artefacts/foreign-travel-advice/albania.json").
      with(:body => hash_including(
        'slug' => 'foreign-travel-advice/albania',
        'name' => 'Albania travel advice',
        'description' => 'The overview',
        'indexable_content' => 'Summary Part One Body text',
        'kind' => 'travel-advice',
        'owning_app' => 'travel-advice-publisher',
        'rendering_app' => 'frontend',
        'state' => 'live'
    ))
  end

  scenario "save and publish a minor update to an edition" do
    Timecop.travel(3.days.ago) do
      @old_edition = FactoryGirl.create(:published_travel_advice_edition, :country_slug => 'albania',
                                        :summary => "## The summaryy",
                                        :change_description => "Some things changed", :minor_update => false)
    end
    @edition = FactoryGirl.create(:draft_travel_advice_edition, :country_slug => 'albania')

    WebMock.stub_request(:put, %r{\A#{GdsApi::TestHelpers::Panopticon::PANOPTICON_ENDPOINT}/artefacts}).
      to_return(:status => 200, :body => "{}")

    now = Time.now.utc
    Timecop.freeze(now) do
      visit "/admin/editions/#{@edition.to_param}/edit"

      fill_in "Summary", :with => "## The summary"
      check "Minor update"

      click_on "Save & Publish"
    end

    @edition.reload
    @edition.should be_published
    @edition.change_description.should == "Some things changed"

    @edition.published_at.should == @old_edition.published_at
    action = @edition.actions.last
    action.request_type.should == Action::PUBLISH
    action.comment.should == "Minor update"
  end

  scenario "attempting to edit a published edition" do
    @edition = FactoryGirl.create(:published_travel_advice_edition, :country_slug => 'albania')
    @draft = FactoryGirl.create(:draft_travel_advice_edition, :country_slug => 'albania')

    visit "/admin/editions/#{@edition.to_param}/edit"

    page.should_not have_content "Add new part"
    page.should have_css("#edition_title[@disabled='disabled']")
    page.should have_css("#edition_overview[@disabled='disabled']")
    page.should have_css("#edition_summary[@disabled='disabled']")
    page.should have_css(".btn-success[@disabled='disabled']")
    page.should_not have_button("Save & Publish")
  end

  scenario "preview an edition" do
    @edition = FactoryGirl.create(:published_travel_advice_edition, :country_slug => 'albania')
    visit "/admin/editions/#{@edition.to_param}/edit"

    page.should have_selector("a[href^='http://private-frontend.dev.gov.uk/foreign-travel-advice/albania?edition=1']", :text => "Preview saved version")
  end

  scenario "create a note" do
    @edition = FactoryGirl.create(:travel_advice_edition, :country_slug => 'australia', :state => 'draft')
    visit "/admin/editions/#{@edition.to_param}/edit"

    within(:css, ".tabbable .nav") do
      click_on "History & Notes"
    end

    within(:css, "#history") do
      fill_in "Note", :with => "This is a test comment"
      click_on "Add Note"
    end

    page.should have_content("This is a test comment")
  end

  scenario "Set the alert status for an edition" do
    @edition = FactoryGirl.create(:travel_advice_edition, :country_slug => 'australia', :state => 'draft')
    visit "/admin/editions/#{@edition.to_param}/edit"

    page.should have_unchecked_field("The FCO advise against all but essential travel to parts of the country")
    page.should have_unchecked_field("The FCO advise against all travel to parts of the country")
    page.should have_unchecked_field("The FCO advise against all but essential travel to the whole country")
    page.should have_unchecked_field("The FCO advise against all travel to the whole country")

    check "The FCO advise against all but essential travel to parts of the country"
    check "The FCO advise against all travel to parts of the country"

    click_on "Save"

    page.should have_checked_field("The FCO advise against all but essential travel to parts of the country")
    page.should have_checked_field("The FCO advise against all travel to parts of the country")
    page.should have_unchecked_field("The FCO advise against all but essential travel to the whole country")
    page.should have_unchecked_field("The FCO advise against all travel to the whole country")

    uncheck "The FCO advise against all but essential travel to parts of the country"
    uncheck "The FCO advise against all travel to parts of the country"

    click_on "Save"

    page.should have_unchecked_field("The FCO advise against all but essential travel to parts of the country")
    page.should have_unchecked_field("The FCO advise against all travel to parts of the country")
    page.should have_unchecked_field("The FCO advise against all but essential travel to the whole country")
    page.should have_unchecked_field("The FCO advise against all travel to the whole country")
  end

  scenario "managing images for an edition" do
    @edition = FactoryGirl.create(:travel_advice_edition, :country_slug => 'australia', :state => 'draft')

    file_one = File.open(Rails.root.join("spec","fixtures","uploads","image.jpg"))
    file_two = File.open(Rails.root.join("spec","fixtures","uploads","image_two.jpg"))

    asset_one = OpenStruct.new(:id => 'http://asset-manager.dev.gov.uk/assets/an_image_id', :file_url => 'http://path/to/image.jpg')
    asset_two = OpenStruct.new(:id => 'http://asset-manager.dev.gov.uk/assets/another_image_id', :file_url => 'http://path/to/image_two.jpg')

    TravelAdvicePublisher.asset_api.should_receive(:create_asset).and_return(asset_one)

    TravelAdvicePublisher.asset_api.stub(:asset).with("an_image_id").and_return(asset_one)
    TravelAdvicePublisher.asset_api.stub(:asset).with("another_image_id").and_return(asset_two)

    visit "/admin/editions/#{@edition.to_param}/edit"

    page.should have_field("Upload a new map image", :type => "file")
    attach_file("Upload a new map image", file_one.path)
    click_on "Save"

    within(:css, ".uploaded-image") do
      page.should have_selector("img[src$='image.jpg']")
    end

    # ensure image is not removed on save
    click_on "Save"

    within(:css, ".uploaded-image") do
      page.should have_selector("img[src$='image.jpg']")
    end

    # replace image
    TravelAdvicePublisher.asset_api.should_receive(:create_asset).and_return(asset_two)

    attach_file("Upload a new map image", file_two.path)
    click_on "Save"

    within(:css, ".uploaded-image") do
      page.should have_selector("img[src$='image_two.jpg']")
    end

    # remove image
    check "Remove image?"
    click_on "Save"

    page.should_not have_selector(".uploaded-image")
  end

  scenario "managing documents for an edition" do
    @edition = FactoryGirl.create(:travel_advice_edition, :country_slug => 'australia', :state => 'draft')

    file_one = File.open(Rails.root.join("spec","fixtures","uploads","document.pdf"))
    file_two = File.open(Rails.root.join("spec","fixtures","uploads","document_two.pdf"))

    asset_one = OpenStruct.new(:id => 'http://asset-manager.dev.gov.uk/assets/a_document_id', :name => "document.pdf", :file_url => 'http://path/to/document.pdf')
    asset_two = OpenStruct.new(:id => 'http://asset-manager.dev.gov.uk/assets/another_document_id', :name => "document_two.pdf", :file_url => 'http://path/to/document_two.pdf')

    TravelAdvicePublisher.asset_api.should_receive(:create_asset).and_return(asset_one)

    TravelAdvicePublisher.asset_api.stub(:asset).with("a_document_id").and_return(asset_one)
    TravelAdvicePublisher.asset_api.stub(:asset).with("another_document_id").and_return(asset_two)

    visit "/admin/editions/#{@edition.to_param}/edit"

    page.should have_field("Upload a new PDF", :type => "file")
    attach_file("Upload a new PDF", file_one.path)
    click_on "Save"

    within(:css, ".uploaded-document") do
      page.should have_link("Download document.pdf", :href => "http://path/to/document.pdf")
    end

    # ensure document is not removed on save
    click_on "Save"

    within(:css, ".uploaded-document") do
      page.should have_link("Download document.pdf", :href => "http://path/to/document.pdf")
    end

    # replace document
    TravelAdvicePublisher.asset_api.should_receive(:create_asset).and_return(asset_two)

    attach_file("Upload a new PDF", file_two.path)
    click_on "Save"

    within(:css, ".uploaded-document") do
      page.should have_link("Download document_two.pdf", :href => "http://path/to/document_two.pdf")
    end

    # remove document
    check "Remove PDF?"
    click_on "Save"

    page.should_not have_selector(".uploaded-document")
  end

  context "workflow 'Save & Publish' button" do
    scenario "does not appear for archived editions" do
      @edition = FactoryGirl.create(:archived_travel_advice_edition, :country_slug => 'albania')
      visit "/admin/editions/#{@edition.to_param}/edit"
      page.should_not have_button("Save & Publish")
    end

    scenario "does not appear for published editions" do
      @edition = FactoryGirl.create(:published_travel_advice_edition, :country_slug => 'albania')
      visit "/admin/editions/#{@edition.to_param}/edit"
      page.should_not have_button("Save & Publish")
    end
  end
end