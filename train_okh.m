function train_okh(run_trial, opts)

	global Xtrain Ytrain

	train_time  = zeros(1, opts.ntrials);
	update_time = zeros(1, opts.ntrials);
	bit_flips   = zeros(1, opts.ntrials);
	parfor t = 1:opts.ntrials
		if run_trial(t) == 0
			myLogInfo('Trial %02d not required, skipped', t);
			continue;
		end
		myLogInfo('%s: %d trainPts, random trial %d', opts.identifier, opts.noTrainingPoints, t);

		% randomly set test checkpoints (to better mimic real scenarios)
		test_iters      = zeros(1, opts.ntests);
		test_iters(1)   = 1;
		test_iters(end) = opts.noTrainingPoints/2;
		interval = round(opts.noTrainingPoints/2/(opts.ntests-1));
		for i = 1:opts.ntests-2
			iter = interval*i + randi([1 round(interval/3)]) - round(interval/6);
			test_iters(i+1) = iter;
		end
		prefix = sprintf('%s/trial%d', opts.expdir, t);

		% do SGD optimization
		[train_time(t), update_time(t), bit_flips(t)] = OKH(Xtrain, Ytrain, ...
			prefix, test_iters, t, opts);
	end

	myLogInfo('Training time (total): %.2f +/- %.2f', mean(train_time), std(train_time));
	if strcmp(opts.mapping, 'smooth')
		myLogInfo('      Bit flips (per): %.4g +/- %.4g', mean(bit_flips), std(bit_flips));
	end
end


function [train_time, update_time, bitflips] = OKH(...
		Xtrain, Ytrain, prefix, test_iters, trialNo, opts)

	tic;
	% sample support samples (300) from the FIRST HALF of training set
	nhalf = floor(size(Xtrain, 1)/2);
	ind = randperm(nhalf, 300);
	Xanchor = Xtrain(ind, :);

	% estimate sigma for Gaussian kernel using samples from the SECOND HALF
	ind = randperm(nhalf, 2000);
	Xval = Xtrain(nhalf+ind, :);
	Kval = sqdist(Xval', Xanchor');
	sigma = mean(mean(Kval, 2));
	myLogInfo('Estimated sigma = %g', sigma);
	clear Xval Kval

  % preliminary for testing
  % kernel mapping the whole set
  KX = exp(-0.5*sqdist(Xtrain', Xanchor')/sigma^2)';
  KX = [KX; ones(1,size(KX,2))];
	%clear Xanchor

  % init
	[d, ntrain_all] = size(KX);
  r = opts.nbits;
  para.c = opts.c; %0.1;
  para.alpha = opts.alpha; %0.2;
  para.anchor = Xanchor;
  %W = rand(d+1,r)-0.5;
  W = rand(d,r)-0.5;
	H = [];

	bitflips = 0;
	update_time = 0;
	train_time = toc;
	myLogInfo('Preprocessing took %f sec', train_time);

  %rX = KX(:,idxTrain); %set being search in testing 
  %tX = KX(:,idxTest); %query set in testing

	number_iterations = opts.noTrainingPoints/2;
	myLogInfo('[T%02d] %d training iterations', trialNo, number_iterations);

  for i = 1:number_iterations
    idx_i = Ytrain(2*i-1); %idxTrain(dataIdx(2*i-1));
    idx_j = Ytrain(2*i);   %idxTrain(dataIdx(2*i));
    s = 2*(idx_i==idx_j)-1;
    
    xi = KX(:, 2*i-1); %KX(:,idx_i);
    xj = KX(:, 2*i);   %X(:,idx_j);

    % hash function update
    t_ = tic;
    W = OKHlearn(xi,xj,s,W,para);
    train_time = train_time + toc(t_);


		% KH: update table
		if i == 1 || i == number_iterations || ...
				(opts.update_interval == 2 && i == number_iterations) || ...
				(opts.update_interval > 2 && ~mod(i, opts.update_interval/2))
			t_ = tic;
			% NOTE assuming smooth mapping
			Hnew = (W' * KX > 0);
			if ~isempty(H)
				bitdiff = xor(H, Hnew);
				bitdiff = sum(bitdiff(:))/ntrain_all;
				bitflips = bitflips + bitdiff;
				myLogInfo('[T%02d] HT update @%d, bitdiff=%g', trialNo, i, bitdiff);
			else
				myLogInfo('[T%02d] HT udpate @%d', trialNo, i);
			end
			H = Hnew;
			update_time = update_time + toc(t_);
		end

		% KH: save intermediate model
		if ismember(i, test_iters)
			F = sprintf('%s_iter%d.mat', prefix, i);
			save(F, 'W', 'H', 'bitflips', 'train_time', 'update_time');
			if ~opts.windows, unix(['chmod o-w ' F]); end  % matlab permission bug

			myLogInfo('[T%02d] (%d/%d) OKH %.2fs, HTU %.2fs, #BF=%g', ...
				trialNo, i, number_iterations, train_time, update_time, bitflips);
		end

  end

	% KH: save final model, etc
	F = [prefix '.mat'];
	save(F, 'W', 'H', 'bitflips', 'train_time', 'update_time', 'test_iters', ...
		'Xanchor', 'sigma');
	if ~opts.windows, unix(['chmod o-w ' F]); end % matlab permission bug
	myLogInfo('[T%02d] Saved: %s\n', trialNo, F);
end