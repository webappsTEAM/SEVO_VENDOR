import { createContext, useContext } from 'react';

export const ACTIVE_QUEUE_STATUSES = [
  'assigned',
  'accepted',
  'on_the_way',
  'en_route',
  'arrived',
  'inspection_in_progress',
  'in_progress',
  'quotation_sent',
  'on_hold',
  'proof_submitted',
];

export const EmployeeRuntimeContext = createContext(null);

export function useEmployeeRuntime() {
  const context = useContext(EmployeeRuntimeContext);
  if (!context) {
    throw new Error('useEmployeeRuntime must be used within an EmployeeRuntimeProvider');
  }
  return context;
}
