require 'spec_helper'

require 'fleet/service_definition'

describe Fleet::Client do

  describe '#initialize' do

    after do
      Fleet.reset
    end

    Fleet::Configuration::VALID_OPTIONS_KEYS.each do |option|
      it "inherits default #{option} value from Panamax" do
        client = Fleet::Client.new
        expect(client.send(option)).to eql(Fleet.send(option))
      end

      it "overrides default for #{option} when specified" do
        client = Fleet::Client.new(option => :foo)
        expect(client.send(option)).to eql(:foo)
      end
    end
  end

  describe '#load' do

    let(:name) { 'foo.service' }
    let(:service_def) { { 'Unit' => { 'Description' => 'bar' } } }
    let(:sd) { Fleet::ServiceDefinition.new(name, service_def) }

    context 'when a service definition is provided' do
      before do
        allow(subject).to receive(:create_unit).and_return(nil)
        allow(subject).to receive(:create_job).and_return(nil)
        allow(subject).to receive(:update_job_target_state).and_return(nil)
        allow(Fleet::ServiceDefinition).to receive(:new).and_return(sd)
      end

      it 'invokes #create_unit' do
        expect(subject).to receive(:create_unit)
          .with(sd.sha1, sd.to_unit)

        subject.load(name, service_def)
      end

      it 'invokes #create_job' do
        expect(subject).to receive(:create_job)
          .with(sd.name, sd.to_job)

        subject.load(name, service_def)
      end

      it 'invokes #update_job_target_state' do
        expect(subject).to receive(:update_job_target_state)
          .with(sd.name, :loaded)

        subject.load(name, service_def)
      end

      context 'when sync=true is set' do

        let(:fleet_state) do
          { 'node' => { 'value' => '{ "loadState": "loaded" }' } }
        end

        before do
          allow(subject).to receive(:get_state).and_return(fleet_state)
        end

        it 'checks the job state' do
          expect(subject).to receive(:get_state).with(sd.name)
          subject.load(name, service_def, sync=true)
        end
      end

      context 'when #create_unit raises PreconditionFailed' do

        before do
          allow(subject).to receive(:create_unit)
            .and_raise(Fleet::PreconditionFailed.new('boom'))
        end

        it 'does not blow up' do
          expect { subject.load(name, service_def) }.to_not raise_error
        end
      end

      context 'when #create_unit raises something other than PreconditionFailed' do

        before do
          allow(subject).to receive(:create_unit)
            .and_raise(Fleet::BadRequest.new('boom'))
        end

        it 'propagates the error' do
          expect { subject.load(name, service_def) }.to(raise_error(Fleet::BadRequest))
        end
      end

      context 'when #create_job raises PreconditionFailed' do

        before do
          allow(subject).to receive(:create_job)
            .and_raise(Fleet::PreconditionFailed.new('boom'))
        end

        it 'does not blow up' do
          expect { subject.load(name, service_def) }.to_not raise_error
        end
      end

      context 'when #create_job raises something other than PreconditionFailed' do

        before do
          allow(subject).to receive(:create_job)
            .and_raise(Fleet::BadRequest.new('boom'))
        end

        it 'propagates the error' do
          expect { subject.load(name, service_def) }.to(raise_error(Fleet::BadRequest))
        end
      end
    end

    context 'when no service definition is provided' do

      before do
        allow(subject).to receive(:update_job_target_state).and_return(nil)
      end

      it 'does NOT invoke #create_unit' do
        expect(subject).to_not receive(:create_unit)
        subject.load(name)
      end

      it 'does NOT invoke #create_job' do
        expect(subject).to_not receive(:create_job)
        subject.load(name)
      end

      it 'invokes #update_job_target_state' do
        expect(subject).to receive(:update_job_target_state)
          .with(sd.name, :loaded)

        subject.load(name)
      end

      context 'when sync=true is set' do

        let(:fleet_state) do
          { 'node' => { 'value' => '{ "loadState": "loaded" }' } }
        end

        before do
          allow(subject).to receive(:get_state).and_return(fleet_state)
        end

        it 'checks the job state' do
          expect(subject).to receive(:get_state).with(sd.name)
          subject.load(name, nil, sync=true)
        end
      end
    end

    context 'when the supplied name is invalid' do

      let(:name) { 'foo!.service' }

      it 'raises an ArgumentError' do
        expect { subject.load(name, nil) }.to raise_error(ArgumentError, /only contain/)
      end
    end
  end

  describe '#start' do
    let(:service_name) { 'foo.service' }

    before do
      allow(subject).to receive(:update_job_target_state)
    end

    it 'invokes #update_job_target_state' do
      expect(subject).to receive(:update_job_target_state)
        .with(service_name, :launched)

      subject.start(service_name)
    end
  end

  describe '#stop' do
    let(:service_name) { 'foo.service' }

    before do
      allow(subject).to receive(:update_job_target_state)
    end

    it 'invokes #update_job_target_state' do
      expect(subject).to receive(:update_job_target_state)
                         .with(service_name, :loaded)

      subject.stop(service_name)
    end

    context 'when sync=true is set' do

      let(:fleet_state) do
        { 'node' => { 'value' => '{ "load_state": "loaded" }' } }
      end

      before do
        allow(subject).to receive(:get_state).and_return(fleet_state)
      end

      it 'checks the job state' do
        expect(subject).to receive(:get_state).with(service_name)
        subject.stop(service_name, sync=true)
      end
    end
  end

  describe '#unload' do
    let(:service_name) { 'foo.service' }

    before do
      allow(subject).to receive(:update_job_target_state)
    end

    it 'invokes #update_job_target_state' do
      expect(subject).to receive(:update_job_target_state)
                         .with(service_name, :inactive)

      subject.unload(service_name)
    end

    context 'when sync=true is set' do

      before do
        allow(subject).to receive(:get_state).and_raise(Fleet::NotFound, 'boom')
      end

      it 'checks the job state' do
        expect(subject).to receive(:get_state).with(service_name)
        subject.unload(service_name, sync=true)
      end

      context 'when the unload state cannot be achieved' do

        let(:fleet_state) do
          { 'node' => { 'value' => '{ "load_state": "loaded" }' } }
        end

        before do
          allow(subject).to receive(:get_state).and_return(fleet_state)
          allow(subject).to receive(:sleep)
        end

        it 're-checks the state 20 times' do
          expect(subject).to receive(:get_state).exactly(20).times
          subject.unload(service_name, sync=true) rescue nil
        end

        it 'raises an error' do
          expect do
            subject.unload(service_name, sync=true)
          end.to raise_error(Fleet::Error)
        end

      end
    end
  end

  describe '#destroy' do
    let(:service_name) { 'foo.service' }

    before do
      allow(subject).to receive(:delete_job).and_return(nil)
    end

    it 'invokes #delete_job' do

      expect(subject).to receive(:delete_job)
                         .with(service_name)
                         .and_return(nil)

      subject.destroy(service_name)
    end

    context 'when sync=true is set' do

      before do
        allow(subject).to receive(:get_state).and_raise(Fleet::NotFound, 'boom')
      end

      it 'checks the job state' do
        expect(subject).to receive(:get_state).with(service_name)
        subject.destroy(service_name, sync=true)
      end
    end
  end

  describe '#status' do

    let(:service_name) { 'foo.service' }

    let(:fleet_state) do
      { 'node' => { 'value' => '{"load": "loaded", "run": "running"}' } }
    end

    before do
      allow(subject).to receive(:get_state).and_return(fleet_state)
    end

    it 'retrieves service state from the fleet client' do
      expect(subject).to receive(:get_state).with(service_name)
      subject.status(service_name)
    end

    it 'returns the state hash w/ normalized keys' do
      expect(subject.status(service_name)).to eq(load: 'loaded', run: 'running')
    end
  end
end
