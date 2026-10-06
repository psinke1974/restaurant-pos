import { Button } from '@/components/common/input/button';
import React, { useState, useEffect } from 'react';
import { SecurityAction, SecurityManager } from '@/providers/security.provider';
import {cn} from "@/lib/utils.ts";
import {TooManyAttemptsError, userKey, verifyCredentials} from "@/api/db/auth.ts";
import {useDB} from "@/api/db/db.ts";
import {hasModule} from "@/components/security/auth/has-module.ts";
import { useTranslation } from 'react-i18next';

interface PinAuthProps {
  onSuccess: (manager?: SecurityManager) => void;
  onCancel: () => void;
  currentAction?: SecurityAction | null;
}

export const PinAuth: React.FC<PinAuthProps> = ({ 
  onSuccess, 
  onCancel, 
  currentAction
}) => {
  const { t } = useTranslation('auth');
  const db = useDB();
  const [pin, setPin] = useState('');
  const [error, setError] = useState('');
  const [approvers, setApprovers] = useState<SecurityManager[]>([]);
  const [approverKey, setApproverKey] = useState<string | undefined>();

  // Only PIN users whose role grants the module can approve, so list just those.
  useEffect(() => {
    let cancelled = false;
    db.query<[SecurityManager[]]>(
      `SELECT id, first_name, last_name, user_role FROM user
        WHERE deleted_at = NONE AND login_method != 'form'
        ORDER BY first_name, last_name FETCH user_role`
    ).then(([users]) => {
      if (cancelled) return;
      const eligible = (users ?? []).filter(user => hasModule(user, currentAction?.module));
      setApprovers(eligible);
      if (eligible.length === 1) {
        setApproverKey(userKey(eligible[0].id));
      }
    }).catch(error => console.error('Could not load approvers', error));
    return () => {
      cancelled = true;
    };
  }, [currentAction?.module]);

  const handleNumberClick = (num: string) => {
    if (approverKey && pin.length < 4) {
      setPin(prev => prev + num);
      setError('');
    }
  };

  const handleClear = () => {
    setPin('');
    setError('');
  };

  const handleDelete = () => {
    setPin(prev => prev.slice(0, -1));
    setError('');
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    await validatePIN();
  };

  const validatePIN = async () => {
    if (!approverKey) return;
    let manager: SecurityManager | undefined;
    try {
      manager = await verifyCredentials<SecurityManager>(approverKey, pin, 'pin');
    } catch (e) {
      if (e instanceof TooManyAttemptsError) {
        setError(t('login.tooManyAttempts'));
        setPin('');
        return;
      }
    }

    if (manager && hasModule(manager, currentAction?.module)) {
      onSuccess(manager);
    } else {
      setError(t('security.invalidPin', { module: currentAction?.module }));
    }

    setPin('');
  }

  const handleKeyPress = (key: string) => {
    switch (key) {
      case 'Enter':
        handleSubmit({ preventDefault: () => {} } as React.FormEvent);
        break;
      case 'Escape':
        onCancel();
        break;
      case 'Backspace':
        handleDelete();
        break;
      default:
        if (/^[0-9]$/.test(key)) {
          handleNumberClick(key);
        }
        break;
    }
  };

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => handleKeyPress(e.key);
    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [approverKey]);

  useEffect(() => {
    if(approverKey && pin.length === 4){
      validatePIN();
    }
  }, [pin]);

  const btnClasses = 'size-[60px] sm:size-[60px] md:size-[90px] p-0 text-neutral-900 transition-all duration-75 bg-neutral-100 rounded-full text-3xl';

  if (!approverKey) {
    return (
      <div className="space-y-4">
        <div className="text-center text-neutral-600">{t('security.chooseApprover')}</div>
        {approvers.length === 0 ? (
          <div className="alert alert-warning">{t('security.noApprovers', { module: currentAction?.module })}</div>
        ) : (
          <div className="grid grid-cols-2 gap-3">
            {approvers.map(approver => (
              <Button
                key={userKey(approver.id)}
                type="button"
                variant="secondary"
                className="lg truncate"
                onClick={() => {
                  setError('');
                  setPin('');
                  setApproverKey(userKey(approver.id));
                }}
              >
                {`${approver.first_name ?? ''} ${approver.last_name ?? ''}`.trim()}
              </Button>
            ))}
          </div>
        )}
      </div>
    );
  }

  const approver = approvers.find(item => userKey(item.id) === approverKey);

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="flex items-center justify-center gap-3 text-lg">
        {approvers.length > 1 && (
          <button
            type="button"
            className="btn btn-flat"
            onClick={() => {
              setPin('');
              setError('');
              setApproverKey(undefined);
            }}
          >
            ←
          </button>
        )}
        <span>{approver ? `${approver.first_name ?? ''} ${approver.last_name ?? ''}`.trim() : ''}</span>
      </div>
      <div>
        {/*{error && (*/}
        {/*  <div className="my-4 alert alert-danger">{error}</div>*/}
        {/*)}*/}
        
        {/* PIN Dots Display */}
        <div className={
          cn("flex justify-center space-x-2 mb-6", !!error && 'login-error')
        }>
          {Array.from({ length: 4 }, (_, i) => (
            <div
              key={i}
              className={`w-6 h-6 rounded-full border-2 flex items-center justify-center ${
                i < pin.length 
                  ? 'bg-gray-900 border-gray-900' 
                  : 'bg-gray-100 border-gray-300'
              }`}
            >
              {i < pin.length && (
                <div className="w-3 h-3 bg-white rounded-full" />
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Numeric Keypad */}
      <div className="flex justify-center ">
        <div className="wrapper w-[300px]">
          <div className="grid grid-cols-3 gap-2 sm:gap-5 place-items-center">
            {['1', '2', '3', '4', '5', '6', '7', '8', '9'].map((num) => (
              <button
                key={num}
                type="button"
                onClick={() => handleNumberClick(num)}
                className={btnClasses}
              >
                {num}
              </button>
            ))}
            
            <button
              type="button"
              onClick={handleDelete}
              className={
                cn(btnClasses, 'bg-danger-500 pressable text-white')
              }
            >
              ←
            </button>
            
            <button
              type="button"
              onClick={() => handleNumberClick('0')}
              className={btnClasses}
            >
              0
            </button>
            
            <button
              type="button"
              onClick={handleClear}
              className={
                cn(btnClasses, 'bg-danger-500 pressable text-white')
              }
            >
              C
            </button>
          </div>
        </div>
      </div>

      {/*<div className="mx-auto flex space-x-3 pt-5 w-[400px] mt-5">*/}
      {/*  <Button*/}
      {/*    type="button"*/}
      {/*    onClick={onCancel}*/}
      {/*    variant="secondary"*/}
      {/*    className="flex-1 lg"*/}
      {/*  >*/}
      {/*    Cancel*/}
      {/*  </Button>*/}
      {/*  <Button*/}
      {/*    type="submit"*/}
      {/*    className="flex-1 lg"*/}
      {/*    variant="primary"*/}
      {/*    active*/}
      {/*  >*/}
      {/*    Confirm*/}
      {/*  </Button>*/}
      {/*</div>*/}
    </form>
  );
};
